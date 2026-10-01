"use strict";

const http = require("node:http");
const https = require("node:https");
const fs = require("node:fs");
const path = require("node:path");
const { URL } = require("node:url");
const { execFile } = require("node:child_process");

const port = Number(process.env.PORT || 3909);
const host = process.env.HOST || "127.0.0.1";
const CACHE_DIR = process.env.CACHE_DIR || "/srv/lslegacy/musicbox";
const STATE_DIR = process.env.STATE_DIR || "/srv/lslegacy/state";
const TOKEN_FILE = process.env.MUSICBOX_TOKEN_FILE || path.join(STATE_DIR, "musicbox-token");
const MAX_DURATION_SECONDS = Number(process.env.MAX_DURATION_SECONDS || 900);
const MAX_AUDIO_BYTES = Number(process.env.MAX_AUDIO_BYTES || 128 * 1024 * 1024);
const AUDIO_EXTENSIONS = ["m4a", "webm", "mp3", "ogg", "wav", "opus"];
const activeDownloads = new Map();
const activeResolves = new Map();

fs.mkdirSync(CACHE_DIR, { recursive: true, mode: 0o750 });
fs.mkdirSync(STATE_DIR, { recursive: true, mode: 0o750 });

function loadOrCreateApiToken() {
  try {
    const current = fs.readFileSync(TOKEN_FILE, "utf8").trim();
    if (current.length >= 32) return current;
  } catch (error) {
    if (error.code !== "ENOENT") throw error;
  }

  const token = require("node:crypto").randomBytes(48).toString("base64url");
  const temp = `${TOKEN_FILE}.${process.pid}.part`;
  fs.writeFileSync(temp, `${token}\n`, { mode: 0o600, flag: "wx" });
  fs.renameSync(temp, TOKEN_FILE);
  fs.chmodSync(TOKEN_FILE, 0o600);
  return token;
}

const apiToken = loadOrCreateApiToken();

function isAuthorized(req) {
  const supplied = req.headers["x-musicbox-token"];
  if (typeof supplied !== "string") return false;
  const expectedBuffer = Buffer.from(apiToken);
  const suppliedBuffer = Buffer.from(supplied);
  return expectedBuffer.length === suppliedBuffer.length && require("node:crypto").timingSafeEqual(expectedBuffer, suppliedBuffer);
}

// Helper POST JSON request with Timeout
function requestPostJson(urlStr, bodyObj, timeoutMs = 30000) {
  return new Promise((resolve, reject) => {
    const url = new URL(urlStr);
    const bodyData = JSON.stringify(bodyObj);

    const req = https.request({
      hostname: url.hostname,
      port: url.port || 443,
      path: url.pathname + url.search,
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "Content-Length": Buffer.byteLength(bodyData),
        "User-Agent": "Mozilla/5.0"
      },
      timeout: timeoutMs
    }, (res) => {
      let data = "";
      res.on("data", (chunk) => { data += chunk; });
      res.on("end", () => {
        if (res.statusCode >= 200 && res.statusCode < 300) {
          try {
            resolve(JSON.parse(data));
          } catch (e) {
            reject(new Error("Invalid JSON response: " + data));
          }
        } else {
          reject(new Error(`HTTP status ${res.statusCode}: ${data}`));
        }
      });
    });

    req.on("timeout", () => {
      req.destroy();
      reject(new Error(`Request timed out after ${timeoutMs}ms`));
    });

    req.on("error", reject);
    req.write(bodyData);
    req.end();
  });
}

// Fallback Extractor: Local yt-dlp
function extractWithYtDlp(youtubeUrl) {
  return new Promise((resolve, reject) => {
    const args = [
      "--dump-single-json",
      "--no-playlist",
      "--no-warnings",
      "-f",
      "bestaudio",
      youtubeUrl
    ];

    execFile("yt-dlp", args, { timeout: 60000, maxBuffer: 10 * 1024 * 1024 }, (error, stdout, stderr) => {
      if (error) {
        return reject(new Error(`yt-dlp failed: ${stderr || error.message}`));
      }

      try {
        const info = JSON.parse(stdout);
        const requested = Array.isArray(info.requested_downloads) ? info.requested_downloads[0] : null;
        const streamUrl = requested?.url || info.url;
        const ext = requested?.ext || info.ext || "webm";

        if (!streamUrl || !/^https?:\/\//.test(streamUrl)) {
          throw new Error("yt-dlp did not return a playable URL");
        }

        resolve({
          title: info.title || "YouTube Audio",
          url: streamUrl,
          duration: Number(info.duration) || 0,
          ext
        });
      } catch (err) {
        reject(new Error(`Failed to parse yt-dlp output: ${err.message}`));
      }
    });
  });
}

// Primary Extractor with Fallback Strategy
async function resolveAudioStreamOnce(videoId) {
  const youtubeUrl = `https://www.youtube.com/watch?v=${videoId}`;

  // Strategy 1: Attempt GenDownload API
  try {
    console.log(`[Resolve:${videoId}] Requesting GenDownload API...`);
    const info = await requestPostJson("https://gendownload.com/api/extract", { url: youtubeUrl });

    if (info && info.formats) {
      const format = info.formats.find(f => f.type === "audio") || info.formats[0];
      if (format && format.url) {
        return {
          title: info.title || videoId,
          duration: Number(info.duration) || 0,
          url: format.url,
          ext: format.ext || "m4a"
        };
      }
    }
  } catch (err) {
    console.warn(`[Resolve:${videoId}] GenDownload failed (${err.message}). Trying yt-dlp fallback...`);
  }

  // Strategy 2: Fallback to local yt-dlp binary
  try {
    const fallbackData = await extractWithYtDlp(youtubeUrl);
    console.log(`[Resolve:${videoId}] ✅ Resolved using yt-dlp fallback!`);
    return {
      title: fallbackData.title,
      duration: fallbackData.duration,
      url: fallbackData.url,
      ext: fallbackData.ext
    };
  } catch (err) {
    console.error(`[Resolve:${videoId}] ❌ yt-dlp fallback failed:`, err.message);
    throw new Error("Unable to extract stream from primary or fallback endpoints.");
  }
}

function resolveAudioStream(videoId) {
  if (activeResolves.has(videoId)) {
    return activeResolves.get(videoId);
  }

  const promise = resolveAudioStreamOnce(videoId)
    .finally(() => activeResolves.delete(videoId));

  activeResolves.set(videoId, promise);
  return promise;
}

function normalizeExtension(ext) {
  const normalized = String(ext || "").toLowerCase().replace(/^\./, "");
  return AUDIO_EXTENSIONS.includes(normalized) ? normalized : "webm";
}

function findCachedFilename(id) {
  const exactPath = path.join(CACHE_DIR, id);
  if (fs.existsSync(exactPath) && fs.statSync(exactPath).isFile() && fs.statSync(exactPath).size > 0) {
    return id;
  }

  const baseId = id.includes(".") ? id.substring(0, id.lastIndexOf(".")) : id;

  for (const ext of AUDIO_EXTENSIONS) {
    const filename = `${baseId}.${ext}`;
    const candidate = path.join(CACHE_DIR, filename);
    if (fs.existsSync(candidate) && fs.statSync(candidate).isFile() && fs.statSync(candidate).size > 0) {
      return filename;
    }
  }

  return null;
}

// Helper Download File
function downloadFile(urlStr, destPath) {
  return new Promise((resolve, reject) => {
    const partialPath = `${destPath}.part`;
    let settled = false;

    function fail(err) {
      if (settled) return;
      settled = true;
      fs.unlink(partialPath, () => {});
      reject(err);
    }

    function getUrl(targetUrl, redirects = 0) {
      if (redirects > 5) {
        fail(new Error("Too many redirects"));
        return;
      }

      const url = new URL(targetUrl);
      const client = url.protocol === "https:" ? https : http;

      const request = client.get(targetUrl, {
        headers: {
          "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
        }
      }, (res) => {
        if ([301, 302, 307, 308].includes(res.statusCode)) {
          const nextUrl = res.headers.location;
          if (nextUrl) {
            res.resume();
            getUrl(new URL(nextUrl, targetUrl).toString(), redirects + 1);
            return;
          }
        }

        if (res.statusCode !== 200) {
          res.resume();
          fail(new Error(`Tải file thất bại, HTTP Status: ${res.statusCode}`));
          return;
        }

        const contentLength = Number(res.headers["content-length"] || 0);
        if (contentLength > MAX_AUDIO_BYTES) {
          res.resume();
          fail(new Error("Audio exceeds cache size limit"));
          return;
        }

        const fileStream = fs.createWriteStream(partialPath);
        let downloadedBytes = 0;
        res.on("data", (chunk) => {
          downloadedBytes += chunk.length;
          if (downloadedBytes > MAX_AUDIO_BYTES) res.destroy(new Error("Audio exceeds cache size limit"));
        });
        res.pipe(fileStream);

        fileStream.on("finish", () => {
          fileStream.close((err) => {
            if (err) {
              fail(err);
              return;
            }

            fs.rename(partialPath, destPath, (renameErr) => {
              if (renameErr) {
                fail(renameErr);
                return;
              }
              settled = true;
              resolve();
            });
          });
        });

        fileStream.on("error", (error) => {
          res.destroy();
          fail(error);
        });
        res.on("error", (error) => {
          fileStream.destroy();
          fail(error);
        });
      });

      request.setTimeout(60000, () => {
        request.destroy(new Error("Audio download timed out after 60000ms"));
      });
      request.on("error", fail);
    }

    fs.unlink(partialPath, () => {});
    getUrl(urlStr);
  });
}

async function downloadFileWithRetry(urlStr, destPath, attempts = 3) {
  let lastError;

  for (let attempt = 1; attempt <= attempts; attempt += 1) {
    try {
      await downloadFile(urlStr, destPath);
      return;
    } catch (err) {
      lastError = err;
      if (attempt < attempts) {
        await new Promise(resolve => setTimeout(resolve, attempt * 2000));
      }
    }
  }

  throw lastError;
}

function startBackgroundDownload(filename, streamData) {
  if (activeDownloads.has(filename)) {
    return activeDownloads.get(filename);
  }

  const targetFilePath = path.join(CACHE_DIR, filename);
  const targetMetaPath = path.join(CACHE_DIR, `${filename}.json`);
  const promise = downloadFileWithRetry(streamData.url, targetFilePath)
    .then(() => {
      const metadata = { title: streamData.title, duration: streamData.duration };
      fs.writeFileSync(targetMetaPath, JSON.stringify(metadata), "utf8");
      console.log(`[Download:${filename}] ✅ Background download completed`);
    })
    .catch((err) => {
      console.error(`[Download:${filename}] Background download failed:`, err.message);
    })
    .finally(() => activeDownloads.delete(filename));

  activeDownloads.set(filename, promise);
  return promise;
}

// ─── Helper Response ───────────────────────────────────────────────────────
function writeJson(res, status, payload) {
  res.writeHead(status, {
    "content-type": "application/json; charset=utf-8",
    "access-control-allow-origin": "*",
    "cache-control": "no-store"
  });
  res.end(JSON.stringify(payload));
}

function setCors(res) {
  res.setHeader("access-control-allow-origin", "*");
  res.setHeader("access-control-allow-methods", "GET, OPTIONS");
  res.setHeader("access-control-allow-headers", "content-type, range, x-musicbox-token");
}

function getPublicBaseUrl(req) {
  if (process.env.PUBLIC_BASE_URL) return process.env.PUBLIC_BASE_URL.replace(/\/$/, "");
  const proto = req.headers["x-forwarded-proto"] || "http";
  const host = req.headers["x-forwarded-host"] || req.headers["host"] || `localhost:${port}`;
  if (host.includes("cdn.lslegacy.net")) return "https://cdn.lslegacy.net/musicbox";
  return `${proto}://${host}`.replace(/\/$/, "");
}

// ─── Stream Local File ───────────────────────────────────────────────────────
function streamLocalFile(filePath, req, res) {
  const stat = fs.statSync(filePath);
  const total = stat.size;

  setCors(res);

  // Safely handle zero-byte empty files created by failed downloads
  if (total === 0) {
    writeJson(res, 404, { error: "File is empty or still downloading" });
    return;
  }

  let contentType = "audio/webm";
  if (filePath.endsWith(".mp3")) contentType = "audio/mpeg";
  else if (filePath.endsWith(".ogg")) contentType = "audio/ogg";
  else if (filePath.endsWith(".wav")) contentType = "audio/wav";
  else if (filePath.endsWith(".m4a")) contentType = "audio/mp4";

  const range = req.headers.range;
  if (range) {
    const parts = range.replace(/bytes=/, "").split("-");
    let start = parseInt(parts[0], 10);
    let end = parts[1] ? parseInt(parts[1], 10) : total - 1;

    // Sanitize ranges to prevent ERR_OUT_OF_RANGE
    if (isNaN(start)) start = 0;
    if (isNaN(end) || end >= total) end = total - 1;

    if (start > end || start >= total) {
      res.writeHead(416, {
        "Content-Range": `bytes */${total}`,
        "access-control-allow-origin": "*"
      });
      res.end();
      return;
    }

    const chunksize = (end - start) + 1;
    const file = fs.createReadStream(filePath, { start, end });

    res.writeHead(206, {
      "Content-Range": `bytes ${start}-${end}/${total}`,
      "Accept-Ranges": "bytes",
      "Content-Length": chunksize,
      "Content-Type": contentType
    });

    file.pipe(res);
  } else {
    res.writeHead(200, {
      "Content-Length": total,
      "Content-Type": contentType,
      "Accept-Ranges": "bytes"
    });
    fs.createReadStream(filePath).pipe(res);
  }
}

// ─── HTTP Server ────────────────────────────────────────────────────────────
const server = http.createServer(async (req, res) => {
  setCors(res);
  if (req.method === "OPTIONS") { res.writeHead(204); res.end(); return; }
  if (req.method !== "GET") { writeJson(res, 405, { error: "method not allowed" }); return; }

  const url = new URL(req.url, `http://${req.headers.host || "localhost"}`);

  if (url.pathname === "/health") {
    writeJson(res, 200, { ok: true, engine: "GenDownload-Bridge-v3.7" });
    return;
  }

  const protectedRoute = url.pathname === "/list" || url.pathname === "/files" || url.pathname.endsWith("/list") || url.pathname.endsWith("/files") || url.pathname.includes("/resolve");
  if (protectedRoute && !isAuthorized(req)) {
    writeJson(res, 401, { error: "unauthorized" });
    return;
  }

  // 1. List / Files Endpoint
  if (url.pathname === "/list" || url.pathname === "/files" || url.pathname.endsWith("/list") || url.pathname.endsWith("/files")) {
    fs.readdir(CACHE_DIR, (err, files) => {
      if (err) {
        writeJson(res, 500, { error: err.message });
        return;
      }

      const audioFiles = [];
      for (const file of files) {
        if (/\.(mp3|webm|ogg|wav|m4a|opus)$/i.test(file)) {
          const filePath = path.join(CACHE_DIR, file);
          let stat;
          try { stat = fs.statSync(filePath); } catch (_) {}
          if (!stat || stat.size === 0) continue;

          const metaPath = path.join(CACHE_DIR, `${file}.json`);
          let title = file;
          let duration = 0;
          if (fs.existsSync(metaPath)) {
            try {
              const meta = JSON.parse(fs.readFileSync(metaPath, "utf8"));
              title = meta.title || file;
              duration = meta.duration || 0;
            } catch (_) {}
          }
          audioFiles.push({
            filename: file,
            title: title,
            duration: duration,
            size: stat.size,
            available: true
          });
        }
      }
      writeJson(res, 200, { files: audioFiles });
    });
    return;
  }

  // 2. Resolve Endpoint
  if (url.pathname.includes("/resolve")) {
    const parts = url.pathname.split("/").filter(Boolean);
    let id = parts[parts.length - 1];

    try { id = decodeURIComponent(id); } catch (_) {}

    if (!id || id === "resolve" || id.includes("..") || id.includes("/") || id.includes("\\")) {
      writeJson(res, 400, { error: "Invalid video ID / filename" });
      return;
    }

    const base = getPublicBaseUrl(req);
    const cachedFilename = findCachedFilename(id);

    // Cache hit
    if (cachedFilename) {
      const metaPath = path.join(CACHE_DIR, `${cachedFilename}.json`);
      let title = cachedFilename;
      let duration = 0;
      if (fs.existsSync(metaPath)) {
        try {
          const meta = JSON.parse(fs.readFileSync(metaPath, "utf8"));
          title = meta.title || title;
          duration = Number(meta.duration) || duration;
        } catch (e) {}
      }
      console.log(`[Resolve:${id}] Cache HIT - "${title}"`);
      writeJson(res, 200, { id, title, duration, url: `${base}/stream/${encodeURIComponent(cachedFilename)}` });
      return;
    }

    // Resolve YouTube ID (11 characters)
    const isYoutube = id.length === 11 && !id.includes(".");
    if (isYoutube) {
      try {
        const streamData = await resolveAudioStream(id);

        const ext = normalizeExtension(streamData.ext);
        if (!Number.isFinite(streamData.duration) || streamData.duration <= 0 || streamData.duration > MAX_DURATION_SECONDS) {
          throw new Error(`Audio duration must be between 1 and ${MAX_DURATION_SECONDS} seconds`);
        }
        const targetFilename = `${id}.${ext}`;
        const targetFilePath = path.join(CACHE_DIR, targetFilename);

        // Download fully before returning a public URL. /stream never resolves upstream.
        if (!fs.existsSync(targetFilePath)) {
          console.log(`[Resolve:${id}] Download triggered: ${targetFilename}`);
          await startBackgroundDownload(targetFilename, streamData);
        }

        if (!findCachedFilename(targetFilename)) {
          throw new Error("Audio download did not produce a cache file");
        }

        const finalStreamUrl = `${base}/stream/${encodeURIComponent(targetFilename)}`;
        console.log(`[Resolve:${id}] Returning Stream URL: ${finalStreamUrl}`);
        writeJson(res, 200, {
          id,
          title: streamData.title,
          duration: streamData.duration,
          url: finalStreamUrl
        });
      } catch (err) {
        console.error(`[Resolve:${id}] Error:`, err.message);
        writeJson(res, 502, { error: err.message || "Failed to resolve stream" });
      }
    } else {
      writeJson(res, 404, { error: "File not found on CDN server" });
    }
    return;
  }

  // 3. Stream Endpoint
  if (url.pathname.includes("/stream")) {
    const rawId = url.pathname.replace(/^.*\/stream\/?/, "");
    let id = rawId;

    try { id = decodeURIComponent(rawId); } catch (_) {}

    if (!id || id.includes("..") || id.includes("/") || id.includes("\\")) {
      writeJson(res, 400, { error: "Invalid ID / filename" });
      return;
    }

    const filePath = path.join(CACHE_DIR, id);

    // If local file is already completely downloaded, stream directly
    if (fs.existsSync(filePath)) {
      streamLocalFile(filePath, req, res);
      return;
    }

    writeJson(res, 404, { error: "File not found on CDN cache directory." });
    return;
  }

  writeJson(res, 404, { error: "Not found" });
});

server.listen(port, host, () => {
  console.log(`[Bridge] GenDownload Proxy Cache Server v3.7 running on http://${host}:${port}`);
});
