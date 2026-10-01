const resourceName = typeof GetParentResourceName === "function" ? GetParentResourceName() : "lv_musicbox";
const state =
{
    visible: false,
    sources: [],
    selectedSourceId: null,
    library:
    {
        favorites: [],
        recent: []
    },
    strings: {},
    tab: "cdn",
    playRequest: null
};

let isDraggingProgress = false;

const renderCache =
{
    sources: null,
    library: null
};

const fallbackStrings =
{
    title: "SpityFork",
    source: "Nguồn Phát",
    play: "Phát",
    pause: "Tạm Dừng",
    resume: "Tiếp Tục",
    stop: "Dừng",
    volume: "Âm Lượng",
    loop: "Lặp Lại",
    favorites: "Yêu Thích",
    recent: "Bài Hát Gần Đây",
    input_placeholder: "Nhập URL YouTube hoặc ID bài hát...",
    favorite: "Lưu",
    remove: "Xóa",
    carry: "Cầm",
    back: "Đeo Lưng",
    drop: "Đặt Xuống",
    pickup: "Thu Hồi",
    no_source: "Không tìm thấy loa",
    idle: "Đang Chờ",
    now_playing: "Đang Phát"
};

const dom = {};

function t(key)
{
    return state.strings[key] || fallbackStrings[key] || key;
}

let lastActionTime = 0;

function isRateLimited()
{
    const now = Date.now();
    if(now - lastActionTime < 1000)
    {
        showToast("Vui lòng chờ trong giây lát trước khi thao tác tiếp!", "warn", 2000);
        return true;
    }
    lastActionTime = now;
    return false;
}

function showToast(message, type = "info", duration = 3000)
{
    if(!dom.toastContainer)
    {
        dom.toastContainer = document.getElementById("toastContainer");
    }
    if(!dom.toastContainer) return;

    const toast = document.createElement("div");
    toast.className = `toast-msg ${type}`;
    toast.innerHTML = `<span>${escapeHtml(message)}</span>`;

    dom.toastContainer.appendChild(toast);

    setTimeout(() =>
    {
        toast.style.opacity = "0";
        toast.style.transform = "translateY(-8px)";
        toast.style.transition = "all 0.3s ease";
        setTimeout(() => toast.remove(), 300);
    }, duration);
}

function isPlayRequestPending()
{
    const phase = state.playRequest && state.playRequest.phase;
    return phase === "requesting" || phase === "resolving" || phase === "buffering" || phase === "starting";
}

function renderPlayRequestStatus()
{
    if(!dom.playBtn)
    {
        return;
    }

    const request = state.playRequest;
    const pending = isPlayRequestPending();
    
    dom.playBtn.disabled = pending;
    dom.playBtn.classList.toggle("loading", pending);
    dom.playBtn.innerHTML = pending
        ? '<span>Đang Tải...</span>'
        : '<span>Phát Ngay</span>';

    if(dom.queueAddBtn)
    {
        dom.queueAddBtn.disabled = pending;
    }

    if(dom.artLoadingOverlay)
    {
        dom.artLoadingOverlay.style.display = pending ? "flex" : "none";
    }

    if(!request)
    {
        return;
    }

    if(dom.statusText)
    {
        dom.statusText.innerHTML = pending
            ? `<i class="fas fa-circle-notch fa-spin"></i> ${escapeHtml(request.message)}`
            : escapeHtml(request.message);
    }
    
    if(dom.footerTrackTitle && pending)
    {
        dom.footerTrackTitle.textContent = request.input;
    }
    
    if(dom.footerTrackStatus)
    {
        dom.footerTrackStatus.style.display = "flex";
        dom.footerTrackStatus.textContent = request.message;
        dom.footerTrackStatus.classList.toggle("error", request.phase === "error");
    }
}

function setPlayRequestPhase(phase, message, payload = {})
{
    const request = state.playRequest;
    
    if(!request || (payload.requestId && payload.requestId !== request.requestId))
    {
        return;
    }
    
    if((request.phase === "playing" || request.phase === "error") && phase !== "error")
    {
        return;
    }

    if(payload.sourceId)
    {
        request.sourceId = payload.sourceId;
    }
    
    request.phase = phase;
    request.message = message || request.message;

    if(phase === "playing" || phase === "error")
    {
        clearTimeout(request.timeout);
        
        const currentRequest = request;
        
        setTimeout(() =>
        {
            if(state.playRequest === currentRequest)
            {
                state.playRequest = null;
                
                render();
            }
        }, phase === "error" ? 4000 : 1500);
    }

    renderPlayRequestStatus();
}

function beginPlayRequest(source, input)
{
    const requestId = `${Date.now()}-${Math.random().toString(36).slice(2, 8)}`;
    const request =
    {
        requestId,
        sourceId: source.id,
        input,
        phase: "requesting",
        message: "Đang Gửi Yêu Cầu Phát Nhạc...",
        timeout: null
    };

    request.timeout = setTimeout(() =>
    {
        if(state.playRequest === request)
        {
            setPlayRequestPhase("error", "Tải nhạc quá lâu hãy thử lại");
        }
    }, 60000);

    state.playRequest = request;
    
    renderPlayRequestStatus();
    return requestId;
}

function updateAudioLoadState(sourceId, phase, message)
{
    const request = state.playRequest;

    if(!request || request.sourceId !== sourceId)
    {
        return;
    }
    
    setPlayRequestPhase(phase, message);
}

function post(name, data = {})
{
    return fetch(`https://${resourceName}/${name}`,
    {
        method: "POST",
        headers:
        {
            "Content-Type": "application/json; charset=UTF-8"
        },
        body: JSON.stringify(data)
    }).catch(() => null);
}

function escapeHtml(value)
{
    return String(value ?? "").replace(/[&<>"']/g, (char) => (
    {
        "&": "&amp;",
        "<": "&lt;",
        ">": "&gt;",
        '"': "&quot;",
        "'": "&#039;"
    }[char]));
}

function selectedSource()
{
    return state.sources.find((source) => source.id === state.selectedSourceId) || null;
}

function sourceIcon(source)
{
    if(source.type === "vehicle")
    {
        return "V";
    }
    
    if(source.type === "speaker")
    {
        return "S";
    }
    return "B";
}

function setVisible(visible)
{
    state.visible = visible;
    
    dom.app.classList.toggle("visible", visible);
    dom.app.setAttribute("aria-hidden", visible ? "false" : "true");
}

function renderSources()
{
    const select = dom.sourceSelect;
    
    if(!select)
    {
        return;
    }

    const cacheKey = JSON.stringify(
    {
        selected: state.selectedSourceId,
        sources: state.sources.map((source) =>
        [
            source.id,
            source.title,
            source.status,
            Math.round(Number(source.distance) || 0)
        ])
    });
    
    if(renderCache.sources === cacheKey || document.activeElement === select)
    {
        return;
    }
    
    renderCache.sources = cacheKey;

    const prevValue = select.value;
    
    select.innerHTML = "";

    if(!state.sources.length)
    {
        const opt = document.createElement("option");
        
        opt.value = "";
        opt.textContent = t("no_source");
        
        select.appendChild(opt);
        return;
    }

    for(const source of state.sources)
    {
        const opt = document.createElement("option");

        opt.value = source.id;

        const distText = source.distance !== undefined && source.distance !== 9999.0 ? ` (${Math.round(source.distance)}m)` : "";
        const statusText = source.title ? ` - ${source.title}` : "";

        opt.textContent = `${source.label || source.id}${distText}${statusText}`;

        if(source.id === state.selectedSourceId)
        {
            opt.selected = true;
        }

        select.appendChild(opt);
    }

    if(!state.selectedSourceId && state.sources.length)
    {
        state.selectedSourceId = state.sources[0].id;

        post("selectSource",
        {
            sourceId: state.selectedSourceId
        });
    }
}

function renderSelected()
{
    const source = selectedSource();

    dom.titleText.textContent = source && source.title ? source.title : t("title");
    dom.statusText.textContent = source
        ? `${source.label || t("source")} • ${source.status || t("idle")}`
        : t("no_source");
    dom.trackInput.placeholder = t("input_placeholder");

    if(source && source.input && document.activeElement !== dom.trackInput && !dom.trackInput.value)
    {
        dom.trackInput.value = source.input;
    }
    else if(!source)
        {
        dom.trackInput.value = "";
    }

    const volume = source ? Math.round((source.volume ?? 0.75) * 100) : Number(dom.volumeRange.value);

    if(document.activeElement !== dom.volumeRange)
    {
        dom.volumeRange.value = String(volume);
    }

    const distance = source ? Math.round(source.distance ?? 25) : Number(dom.distanceRange.value);
    
    if(document.activeElement !== dom.distanceRange)
    {
        dom.distanceRange.value = String(distance);
    }

    if(dom.playPauseBtn)
    {
        if(source && !source.paused && source.title)
        {
            dom.playPauseBtn.innerHTML = '<i class="fas fa-pause"></i>';
        }
        else
        {
            dom.playPauseBtn.innerHTML = '<i class="fas fa-play"></i>';
        }
    }

    if(dom.nowPlayingArt)
    {
        if(source && source.videoId)
        {
            dom.nowPlayingArt.src = `https://i.ytimg.com/vi/${source.videoId}/hqdefault.jpg`;
        }
        else
        {
            dom.nowPlayingArt.src = "https://i.ibb.co/JRmHJ255/lsg.png";
        }
    }

    if(dom.footerTrackTitle)
    {
        dom.footerTrackTitle.textContent = source && source.title ? source.title : t("idle");
    }
    
    if(dom.footerTrackArtist)
    {
        dom.footerTrackArtist.textContent = source && source.input ? (source.input.startsWith("http") ? "Link Trực Tiếp" : "YouTube") : "Hiện Không Phát Nhạc";
    }
    
    if(dom.footerTrackStatus)
    {
        dom.footerTrackStatus.classList.remove("error");
        
        const isPlaying = source && source.title && !source.paused;
        
        dom.footerTrackStatus.style.display = isPlaying ? "flex" : "none";
        if(isPlaying)
        {
            dom.footerTrackStatus.innerHTML = `<div class="equalizer-bars"><span class="eq-bar"></span><span class="eq-bar"></span><span class="eq-bar"></span><span class="eq-bar"></span></div><span>Đang Phát</span>`;
        }
        else
        {
            dom.footerTrackStatus.textContent = "Tạm Dừng";
        }
    }

    dom.deviceActions.classList.toggle("hidden", !source || !source.canMove);

    for(const button of dom.deviceActions.querySelectorAll("button"))
    {
        button.innerHTML = `<i class="fas ${getDeviceActionIcon(button.dataset.deviceAction)}"></i> ${t(button.dataset.deviceAction)}`;
    }
}

function getDeviceActionIcon(action)
{
    if(action === "carry")
    {
        return "fa-hand-holding";
    }
    
    if(action === "back")
    {
        return "fa-tshirt";
    }
    
    if(action === "drop")
    {
        return "fa-arrow-down";
    }
    return "fa-box";
}

function renderRecent()
{
    const list = state.library.recent || [];

    dom.recentList.innerHTML = "";

    if(!list.length)
    {
        const empty = document.createElement("div");

        empty.className = "empty";
        empty.textContent = "Chưa có bài hát nào được nghe gần đây";

        dom.recentList.appendChild(empty);
        return;
    }

    for(const track of list)
    {
        const card = document.createElement("div");

        card.className = "recent-card";

        const thumbnail = track.videoId
            ? `https://i.ytimg.com/vi/${track.videoId}/hqdefault.jpg`
            : "https://i.ibb.co/JRmHJ255/lsg.png";
        
        card.innerHTML = `
            <img class="recent-card-img" src="${thumbnail}" alt="Thumbnail">
            <div class="recent-card-info">
                <div class="recent-card-title">${escapeHtml(track.title || track.input)}</div>
                <div class="recent-card-artist">${escapeHtml(track.videoId ? "YouTube" : "Link trực tiếp")}</div>
            </div>
        `;
        card.addEventListener("click", () =>
        {
            dom.trackInput.value = track.input || track.videoId || "";
            handlePlay();
        });

        dom.recentList.appendChild(card);
    }
}

function renderFavorites()
{
    const list = state.library.favorites || [];

    dom.favoritesList.innerHTML = "";

    if(!list.length)
    {
        const empty = document.createElement("div");

        empty.className = "empty";
        empty.textContent = "No saved tracks";

        dom.favoritesList.appendChild(empty);
        return;
    }

    for(const track of list)
    {
        const row = document.createElement("div");

        row.className = "favorite-row";

        const thumbnail = track.videoId
            ? `https://i.ytimg.com/vi/${track.videoId}/hqdefault.jpg`
            : "https://i.ibb.co/JRmHJ255/lsg.png";

        row.innerHTML = `
            <img class="favorite-img" src="${thumbnail}" alt="Thumbnail">
            <div class="favorite-info">
                <div class="favorite-title">${escapeHtml(track.title || track.input)}</div>
                <div class="favorite-artist">${escapeHtml(track.videoId ? "YouTube" : "Link trực tiếp")}</div>
            </div>
            <div class="favorite-actions">
                <span class="favorite-duration">${track.duration ? formatTime(track.duration) : ""}</span>
                <button class="favorite-btn-action" type="button" data-action="addQueue" title="Thêm vào hàng đợi"><i class="fas fa-plus"></i></button>
                <button class="favorite-btn-action" type="button" data-action="play" title="Phát ngay"><i class="fas fa-play"></i></button>
                <button class="favorite-btn-action danger" type="button" data-action="remove" title="Xóa"><i class="fas fa-trash"></i></button>
            </div>
        `;

        row.querySelector('[data-action="addQueue"]').addEventListener("click", (e) =>
        {
            e.stopPropagation();
            handleQueueAdd(track.input || track.videoId || "");
        });

        row.querySelector('[data-action="play"]').addEventListener("click", (e) =>
        {
            e.stopPropagation();

            dom.trackInput.value = track.input || track.videoId || "";

            handlePlay();
        });

        row.querySelector('[data-action="remove"]').addEventListener("click", (e) =>
        {
            e.stopPropagation();

            post("favorite",
            {
                action: "remove", track
            });
        });

        row.addEventListener("click", () =>
        {
            dom.trackInput.value = track.input || track.videoId || "";
        });

        dom.favoritesList.appendChild(row);
    }
}

const deadTracks = new Set();

function markTrackAsDead(identifier)
{
    if(!identifier) return;
    const cleanId = String(identifier).trim().toLowerCase();
    deadTracks.add(cleanId);

    if(state.library && Array.isArray(state.library.cdnFiles))
    {
        state.library.cdnFiles = state.library.cdnFiles.filter(track =>
        {
            const fn = String(track.filename || "").trim().toLowerCase();
            const tt = String(track.title || "").trim().toLowerCase();
            return fn !== cleanId && tt !== cleanId && !cleanId.includes(fn) && !cleanId.includes(tt);
        });

        renderCdnList();
    }
}

function renderCdnList()
{
    const rawList = (state.library.cdnFiles || []).filter(track =>
    {
        const fn = String(track.filename || "").trim().toLowerCase();
        const tt = String(track.title || "").trim().toLowerCase();
        return !deadTracks.has(fn) && !deadTracks.has(tt);
    });

    const query = (dom.cdnSearchInput ? dom.cdnSearchInput.value : "").trim().toLowerCase();

    const list = query
        ? rawList.filter(track =>
        {
            const title = String(track.title || "").toLowerCase();
            const filename = String(track.filename || "").toLowerCase();
            return title.includes(query) || filename.includes(query);
        })
        : rawList;

    dom.cdnList.innerHTML = "";

    if(!list.length)
    {
        const empty = document.createElement("div");

        empty.className = "empty";
        empty.textContent = query ? "Không tìm thấy bài hát phù hợp" : "Không có nhạc khả dụng trên CDN";

        dom.cdnList.appendChild(empty);
        return;
    }

    for(const track of list)
    {
        const row = document.createElement("div");

        row.className = "favorite-row";

        row.innerHTML = `
            <img class="favorite-img" src="https://i.ibb.co/JRmHJ255/lsg.png" alt="Thumbnail">
            <div class="favorite-info">
                <div class="favorite-title">${escapeHtml(track.title || track.filename)}</div>
                <div class="favorite-artist">${escapeHtml(track.filename)}</div>
            </div>
            <div class="favorite-actions">
                <span class="favorite-duration">${track.duration ? formatTime(track.duration) : ""}</span>
                <button class="favorite-btn-action" type="button" data-action="addQueue" title="Thêm vào hàng đợi"><i class="fas fa-plus"></i></button>
                <button class="favorite-btn-action" type="button" data-action="play" title="Phát ngay"><i class="fas fa-play"></i></button>
            </div>
        `;

        row.querySelector('[data-action="addQueue"]').addEventListener("click", (e) =>
        {
            e.stopPropagation();
            handleQueueAdd(track.filename);
        });

        row.querySelector('[data-action="play"]').addEventListener("click", (e) =>
        {
            e.stopPropagation();

            dom.trackInput.value = track.filename;

            handlePlay();
        });

        row.addEventListener("click", () =>
        {
            dom.trackInput.value = track.filename;
        });

        dom.cdnList.appendChild(row);
    }
}

function renderQueueList()
{
    const source = selectedSource();
    const queue = (source && source.queue) ? source.queue : [];

    if(dom.queueBadge)
    {
        dom.queueBadge.textContent = queue.length;
        dom.queueBadge.style.display = queue.length > 0 ? "inline-block" : "none";
    }

    if(dom.clearQueueBtn)
    {
        dom.clearQueueBtn.style.display = (state.tab === "queue" && queue.length > 0) ? "inline-flex" : "none";
    }

    if(!dom.queueList)
    {
        return;
    }

    dom.queueList.innerHTML = "";

    if(!queue.length)
    {
        const empty = document.createElement("div");

        empty.className = "empty";
        empty.textContent = "Hàng đợi nhạc đang trống";

        dom.queueList.appendChild(empty);
        return;
    }

    queue.forEach((track, idx) =>
    {
        const row = document.createElement("div");

        row.className = "favorite-row";

        const thumbnail = track.videoId
            ? `https://i.ytimg.com/vi/${track.videoId}/hqdefault.jpg`
            : "https://i.ibb.co/JRmHJ255/lsg.png";

        row.innerHTML = `
            <img class="favorite-img" src="${thumbnail}" alt="Thumbnail">
            <div class="favorite-info">
                <div class="favorite-title">${escapeHtml(track.title || track.input)}</div>
                <div class="favorite-artist">${escapeHtml(track.videoId ? "YouTube" : "File nhạc")}</div>
            </div>
            <div class="favorite-actions">
                <span class="favorite-duration">${track.duration ? formatTime(track.duration) : ""}</span>
                <button class="favorite-btn-action danger" type="button" data-action="removeQueue" title="Xóa khỏi hàng đợi"><i class="fas fa-trash"></i></button>
            </div>
        `;

        row.querySelector('[data-action="removeQueue"]').addEventListener("click", (e) =>
        {
            e.stopPropagation();

            handleQueueRemove(idx + 1);
        });

        dom.queueList.appendChild(row);
    });
}

function setLibraryTab(tab)
{
    if(!["cdn", "queue", "favorites", "recent"].includes(tab))
    {
        return;
    }

    state.tab = tab;
    
    dom.tabCdn?.classList.toggle("active", tab === "cdn");
    dom.tabQueue?.classList.toggle("active", tab === "queue");
    dom.tabFavorites?.classList.toggle("active", tab === "favorites");
    dom.tabRecent?.classList.toggle("active", tab === "recent");

    if(dom.recentSection)
    {
        dom.recentSection.hidden = tab !== "recent";
    }
    
    if(dom.librarySection)
    {
        dom.librarySection.hidden = tab === "recent";
    }
    
    if(dom.cdnSearchWrap)
    {
        dom.cdnSearchWrap.style.display = tab === "cdn" ? "flex" : "none";
    }

    if(dom.cdnList)
    {
        dom.cdnList.style.display = tab === "cdn" ? "grid" : "none";
    }

    if(dom.queueList)
    {
        dom.queueList.style.display = tab === "queue" ? "grid" : "none";
    }
    
    if(dom.favoritesList)
    {
        dom.favoritesList.style.display = tab === "favorites" ? "grid" : "none";
    }

    if(dom.clearQueueBtn)
    {
        const source = selectedSource();
        const hasQueue = source && source.queue && source.queue.length > 0;

        dom.clearQueueBtn.style.display = (tab === "queue" && hasQueue) ? "inline-flex" : "none";
    }
    
    if(dom.libraryTitle)
    {
        const titles = {
            cdn: "Nhạc Có Sẵn",
            queue: "Hàng Đợi Nhạc",
            favorites: "Đã Yêu Thích"
        };

        dom.libraryTitle.textContent = titles[tab] || "Bộ Sưu Tập";
    }

    renderQueueList();
}

function renderTabs()
{
    renderFavorites();
    renderRecent();
    renderCdnList();
    renderQueueList();
}

function handleQueueAdd(input)
{
    if(isRateLimited()) return;

    const source = selectedSource();

    if(!source)
    {
        showToast("Chưa chọn nguồn phát!", "warn");
        return;
    }

    const cleanInput = String(input || "").trim();
    if(!cleanInput) return;

    source.queue = source.queue || [];
    source.queue.push({
        input: cleanInput,
        title: cleanInput
    });
    renderQueueList();

    showToast(`Đã thêm "${cleanInput.length > 30 ? cleanInput.substring(0, 30) + '...' : cleanInput}" vào hàng đợi!`, "success");

    const payload = {
        action: "add",
        input: cleanInput
    };

    if(source.virtual || source.targetType === "vehicle")
    {
        payload.targetType = source.targetType || "vehicle";
        payload.vehicleNetId = source.vehicleNetId;
    }
    else
    {
        payload.sourceId = source.id;
    }

    post("queueAction", payload);
}

function handleQueueRemove(index)
{
    const source = selectedSource();

    if(!source)
    {
        return;
    }

    if(source.queue && source.queue[index - 1])
    {
        source.queue.splice(index - 1, 1);
        renderQueueList();
    }

    const payload = {
        action: "remove",
        index
    };

    if(source.virtual || source.targetType === "vehicle")
    {
        payload.targetType = source.targetType || "vehicle";
        payload.vehicleNetId = source.vehicleNetId;
    }
    else
    {
        payload.sourceId = source.id;
    }

    post("queueAction", payload);
}

function handleQueueClear()
{
    const source = selectedSource();

    if(!source)
    {
        return;
    }

    source.queue = [];
    renderQueueList();

    const payload = {
        action: "clear"
    };

    if(source.virtual || source.targetType === "vehicle")
    {
        payload.targetType = source.targetType || "vehicle";
        payload.vehicleNetId = source.vehicleNetId;
    }
    else
    {
        payload.sourceId = source.id;
    }

    post("queueAction", payload);
}

function handleQueueSkip()
{
    const source = selectedSource();

    if(!source)
    {
        return;
    }

    if(source.queue && source.queue.length > 0)
    {
        source.queue.shift();
        renderQueueList();
    }

    const payload = {
        action: "skip"
    };

    if(source.virtual || source.targetType === "vehicle")
    {
        payload.targetType = source.targetType || "vehicle";
        payload.vehicleNetId = source.vehicleNetId;
    }
    else
    {
        payload.sourceId = source.id;
    }

    post("queueAction", payload);
}

function render()
{
    setVisible(state.visible);
    
    renderSources();
    renderSelected();
    renderTabs();
    renderPlayRequestStatus();
}

function currentTrackPayload()
{
    const source = selectedSource();
    const input = dom.trackInput.value.trim() || (source && source.input) || "";
    return {
        input,
        title: (source && source.title) || input,
        videoId: source && source.videoId
    };
}

function handlePlay()
{
    if(isRateLimited()) return;

    const source = selectedSource();
    
    if(!source)
    {
        showToast("Chưa chọn nguồn phát!", "warn");
        return;
    }
    
    if(isPlayRequestPending())
    {
        showToast("Đang nạp bài hát, vui lòng chờ...", "info");
        return;
    }

    const input = dom.trackInput.value.trim();
    
    if(!input)
    {
        showToast("Vui lòng dán URL hoặc nhập tên bài hát!", "warn");
        return;
    }

    AudioEngine.unlock();
    
    showToast("Đang gửi yêu cầu nạp bài hát...", "info", 2000);
    const requestId = beginPlayRequest(source, input);
    const payload =
    {
        input,
        volume: Number(dom.volumeRange.value) / 100,
        loop: false,
        requestId
    };

    if(source.virtual || source.targetType === "vehicle")
    {
        payload.targetType = source.targetType || "vehicle";
        payload.vehicleNetId = source.vehicleNetId;
    }
    else
    {
        payload.sourceId = source.id;
    }

    post("play", payload).then((response) =>
    {
        if(response === null && state.playRequest && state.playRequest.requestId === requestId)
        {
            setPlayRequestPhase("error", "Không gửi được yêu cầu tới Game Client");
        }
    });
}

function handleControl(action, extra = {})
{
    const source = selectedSource();
    
    if(!source || source.virtual)
    {
        return;
    }

    post("control",
    {
        sourceId: source.id,
        action,
        ...extra
    });
}

function getPlayableDuration(source, sound)
{
    const serverDuration = Number(source && source.duration);
    
    if(Number.isFinite(serverDuration) && serverDuration > 0)
    {
        return serverDuration;
    }

    const mediaDuration = Number(sound && sound.audio && sound.audio.duration);
    
    if(Number.isFinite(mediaDuration) && mediaDuration > 0)
    {
        return mediaDuration;
    }
    return 0;
}

function requestSeek(source, targetTime){
    if(!source || !source.url || source.virtual)
    {
        return;
    }

    const duration = getPlayableDuration(source, AudioEngine.items.get(source.id));
    
    let target = Number(targetTime);
    
    if(!Number.isFinite(target))
    {
        return;
    }
    
    target = Math.max(0, duration > 0 ? Math.min(target, duration) : target);

    // Seek immediately on the controlling client and protect that position
    // until the newer server version arrives. Otherwise 250ms audio updates
    // can apply the previous timestamp and pull the slider backwards.
    AudioEngine.seekTo(source.id, target);
    
    post("control",
    {
        sourceId: source.id,
        action: "seek",
        time: target
    });
}

function seekOffset(offset)
{
    const source = selectedSource();
    
    if(!source || !source.url)
    {
        return;
    }

    const sound = AudioEngine.items.get(source.id);
    
    if(sound && sound.audio)
    {
        const duration = getPlayableDuration(source, sound);
        
        let targetTime = sound.audio.currentTime + offset;
        
        if(targetTime < 0)
        {
            targetTime = 0;
        }
        
        if(duration > 0 && targetTime > duration)
        {
            targetTime = duration;
        }
        
        requestSeek(source, targetTime);
    }
}

function bindUi()
{
    dom.app = document.getElementById("app");
    dom.closeBtn = document.getElementById("closeBtn");
    dom.statusText = document.getElementById("statusText");
    dom.titleText = document.getElementById("titleText");

    dom.sourceSelect = document.getElementById("sourceSelect");
    dom.trackInput = document.getElementById("trackInput");
    dom.playBtn = document.getElementById("playBtn");
    dom.playPauseBtn = document.getElementById("playPauseBtn");
    dom.stopBtn = document.getElementById("stopBtn");
    dom.favBtn = document.getElementById("favBtn");

    dom.volumeRange = document.getElementById("volumeRange");
    dom.distanceRange = document.getElementById("distanceRange");

    dom.playbackProgress = document.getElementById("playbackProgress");
    dom.currentTime = document.getElementById("currentTime");
    dom.totalTime = document.getElementById("totalTime");

    dom.prevBtn = document.getElementById("prevBtn");
    dom.nextBtn = document.getElementById("nextBtn");

    dom.recentList = document.getElementById("recentList");
    dom.favoritesList = document.getElementById("favoritesList");
    dom.tabCdn = document.getElementById("tabCdn");
    dom.tabQueue = document.getElementById("tabQueue");
    dom.tabFavorites = document.getElementById("tabFavorites");
    dom.tabRecent = document.getElementById("tabRecent");
    dom.cdnList = document.getElementById("cdnList");
    dom.cdnSearchWrap = document.getElementById("cdnSearchWrap");
    dom.cdnSearchInput = document.getElementById("cdnSearchInput");
    dom.queueList = document.getElementById("queueList");
    dom.queueBadge = document.getElementById("queueBadge");
    dom.queueAddBtn = document.getElementById("queueAddBtn");
    dom.clearQueueBtn = document.getElementById("clearQueueBtn");
    dom.recentSection = document.getElementById("recentSection");
    dom.librarySection = document.getElementById("librarySection");
    dom.libraryTitle = document.getElementById("libraryTitle");
    dom.nowPlayingArt = document.getElementById("nowPlayingArt");
    dom.footerTrackTitle = document.getElementById("footerTrackTitle");
    dom.footerTrackArtist = document.getElementById("footerTrackArtist");
    dom.footerTrackStatus = document.getElementById("footerTrackStatus");
    dom.deviceActions = document.getElementById("deviceActions");

    if(dom.cdnSearchInput)
    {
        dom.cdnSearchInput.addEventListener("input", () => renderCdnList());
    }

    // Tab switching
    if(dom.tabCdn && dom.tabFavorites && dom.tabRecent)
    {
        dom.tabCdn.addEventListener("click", () => setLibraryTab("cdn"));
        dom.tabQueue?.addEventListener("click", () => setLibraryTab("queue"));
        dom.tabFavorites.addEventListener("click", () => setLibraryTab("favorites"));
        dom.tabRecent.addEventListener("click", () => setLibraryTab("recent"));
        
        setLibraryTab(state.tab);
    }

    // Close NUI
    dom.closeBtn.addEventListener("click", () => post("close"));

    // Play Youtube link/ID/filename
    dom.playBtn.addEventListener("click", handlePlay);

    // Queue Add from search bar
    dom.queueAddBtn?.addEventListener("click", () =>
    {
        const input = dom.trackInput.value.trim();
        if(input)
        {
            handleQueueAdd(input);
        }
    });

    // Clear queue button
    dom.clearQueueBtn?.addEventListener("click", handleQueueClear);

    // Play/Pause toggle click
    dom.playPauseBtn.addEventListener("click", () =>
    {
        const source = selectedSource();
        
        if(source)
        {
            handleControl(source.paused ? "resume" : "pause");
        }
    });

    // Stop Playback
    dom.stopBtn.addEventListener("click", () => handleControl("stop"));

    // Save current track to Favorites
    dom.favBtn.addEventListener("click", () =>
    {
        const track = currentTrackPayload();
        
        if(track.input)
        {
            post("favorite",
            {
                action: "add",
                track
            });
        }
    });

    // Volume Adjustment
    dom.volumeRange.addEventListener("change", () =>
    {
        handleControl("volume",
        {
            volume: Number(dom.volumeRange.value) / 100
        });
    });

    // Distance/Speaker Range Adjustment
    dom.distanceRange.addEventListener("change", () =>
    {
        handleControl("distance",
        {
            distance: Number(dom.distanceRange.value)
        });
    });

    // Source Selector dropdown selection change
    dom.sourceSelect.addEventListener("change", () =>
    {
        state.selectedSourceId = dom.sourceSelect.value;
        
        const source = selectedSource();
        
        if(source && source.input)
        {
            dom.trackInput.value = source.input;
        }
        
        post("selectSource",
        {
            sourceId: state.selectedSourceId
        });
        
        render();
    });

    // Progress Bar events to handle user seeking smoothly
    dom.playbackProgress.addEventListener("mousedown", () =>
    {
        isDraggingProgress = true;
    });

    dom.playbackProgress.addEventListener("input", () =>
    {
        isDraggingProgress = true;
        
        const source = selectedSource();
        
        if(source)
        {
            const sound = AudioEngine.items.get(source.id);
            
            if(sound && sound.audio)
            {
                const duration = getPlayableDuration(source, sound);
                const percent = Number(dom.playbackProgress.value) / 100;
                
                dom.currentTime.textContent = formatTime(duration * percent);
            }
        }
    });

    dom.playbackProgress.addEventListener("change", () =>
    {
        isDraggingProgress = false;
        
        const source = selectedSource();
        
        if(!source || !source.url)
        {
            return;
        }

        const sound = AudioEngine.items.get(source.id);
        const duration = getPlayableDuration(source, sound);
        
        if(duration > 0)
        {
            const percent = Number(dom.playbackProgress.value) / 100;
            
            requestSeek(source, duration * percent);
        }
    });

    dom.playbackProgress.addEventListener("mouseup", () =>
    {
        setTimeout(() =>
        {
            isDraggingProgress = false;
        }, 100);
    });

    // Media seek +/- 10s or skip queue
    dom.prevBtn.addEventListener("click", () => seekOffset(-10));
    dom.nextBtn.addEventListener("click", () =>
    {
        const source = selectedSource();
        if(source && source.queue && source.queue.length > 0)
        {
            handleQueueSkip();
        }
        else
        {
            seekOffset(10);
        }
    });

    // Device Actions (Carry, Back, Drop, Pickup)
    for(const button of dom.deviceActions.querySelectorAll("button"))
    {
        button.addEventListener("click", () =>
        {
            const source = selectedSource();
            
            if(!source)
            {
                return;
            }
            
            post("deviceAction",
            {
                sourceId: source.id,
                action: button.dataset.deviceAction
            });
        });
    }

    document.addEventListener("keydown", (event) =>
    {
        AudioEngine.unlock();
        
        if(event.key === "Escape" && state.visible)
        {
            post("close");
        }
    });

    document.addEventListener("pointerdown", () => AudioEngine.unlock(),
    {
        passive: true
    });
}

const AudioEngine = (() =>
{
    const items = new Map();
    
    let ctx = null;
    let resumePromise = null;
    let currentListenerData = null;

    function context()
    {
        if(!ctx)
        {
            const AudioContextClass = window.AudioContext || window.webkitAudioContext;
            
            if(AudioContextClass)
            {
                ctx = new AudioContextClass();
            }
        }
        return ctx;
    }

    function resumeContext()
    {
        const audioContext = context();
        
        if(!audioContext || audioContext.state === "running")
        {
            return Promise.resolve(audioContext);
        }
        
        if(resumePromise)
        {
            return resumePromise;
        }

        resumePromise = audioContext.resume()
            .catch(() => null)
            .finally(() =>
            {
                resumePromise = null;
            });
        return resumePromise;
    }

    function unlock()
    {
        return resumeContext().then(() =>
        {
            for(const sound of items.values())
            {
                sound.tryPlay();
            }
        });
    }

    function setParam(param, value, speed = 0.045)
    {
        if(!param)
        {
            return;
        }
        
        const audioContext = context();
        
        if(audioContext && typeof param.setTargetAtTime === "function")
        {
            param.setTargetAtTime(value, audioContext.currentTime, speed);
        }
        else
        {
            param.value = value;
        }
    }

    function reportError(id, message, fatal = false)
    {
        post("audioError",
        {
            id,
            message: String(message || "audio error"),
            fatal
        });
    }

    function retryUrl(url, attempt)
    {
        if(!/^https:\/\/cdn\.lslegacy\.net\//i.test(url))
        {
            return url;
        }
        
        const separator = url.includes("?") ? "&" : "?";
        return `${url}${separator}lv_retry=${Date.now()}_${attempt}`;
    }

    class SpatialSound
    {
        constructor(data)
        {
            this.id = data.id;
            this.url = data.url;
            this.desired =
            {
                ...data
            };
            this.destroyed = false;
            this.failed = false;
            this.retryCount = 0;
            this.retryTimer = null;
            this.bufferTimer = null;
            this.playPending = false;
            this.localEnded = false;
            this.incomplete = false;
            this.pendingUserSeek = null;
            this.audio = new Audio();
            this.audio.style.display = "none";
            this.audio.crossOrigin = "anonymous";
            this.audio.preload = "auto";
            
            document.body.appendChild(this.audio); // Fix Chromium CEF orphaned audio element bug

            this.audio.loop = !!data.loop;
            this.ready = false;
            this.usingGraph = false;
            this.pendingSeek = null;

            const audioContext = context();
            
            if(audioContext)
            {
                this.source = audioContext.createMediaElementSource(this.audio);
                this.panner = audioContext.createPanner();
                this.filter = audioContext.createBiquadFilter();
                this.compressor = audioContext.createDynamicsCompressor();
                this.gain = audioContext.createGain();
                this.delay = audioContext.createDelay(1.0);
                this.feedback = audioContext.createGain();
                this.wet = audioContext.createGain();

                this.panner.panningModel = "HRTF";
                this.panner.distanceModel = "linear";
                this.filter.type = "lowpass";
                this.delay.delayTime.value = 0.16;
                this.feedback.gain.value = 0.16;
                this.wet.gain.value = 0.0;
                this.compressor.threshold.value = -18;
                this.compressor.knee.value = 18;
                this.compressor.ratio.value = 4;
                this.compressor.attack.value = 0.01;
                this.compressor.release.value = 0.25;

                this.source.connect(this.panner);
                this.panner.connect(this.filter);
                this.filter.connect(this.compressor);
                this.compressor.connect(this.gain);
                this.gain.connect(audioContext.destination);
                this.filter.connect(this.delay);
                this.delay.connect(this.feedback);
                this.feedback.connect(this.delay);
                this.delay.connect(this.wet);
                this.wet.connect(audioContext.destination);
                this.usingGraph = true;
            }

            this.audio.addEventListener("loadedmetadata", () =>
            {
                if(this.hasIncompleteMedia())
                {
                    this.incomplete = true;
                    this.ready = false;
                    this.audio.pause();
                    this.playPending = false;
                    this.scheduleRetry("CDN stream is still being prepared");
                    return;
                }
                
                this.ready = true;
                this.syncTime(true, true);
            });

            this.audio.addEventListener("canplay", () =>
            {
                if(this.hasIncompleteMedia())
                {
                    return;
                }

                this.ready = true;
                this.clearBufferTimer();
                this.syncTime(false, false);
                
                updateAudioLoadState(this.id, "starting", "Audio đã sẵn sàng đang bắt đầu phát nhạc...");
                
                this.tryPlay();
            });

            this.audio.addEventListener("playing", () =>
            {
                this.playPending = false;
                this.failed = false;
                
                if(!this.hasIncompleteMedia())
                {
                    this.retryCount = 0;
                }
                
                this.clearBufferTimer();
                
                updateAudioLoadState(this.id, "playing", "Đang Phát");
            });

            this.audio.addEventListener("waiting", () =>
            {
                updateAudioLoadState(this.id, "buffering", "Mạng chậm đang nạp thêm Audio...");
                
                this.armBufferTimer("buffer timeout");
            });

            this.audio.addEventListener("stalled", () =>
            {
                updateAudioLoadState(this.id, "buffering", "Luồng nhạc bị gián đoạn đang kết nối lại...");
                
                this.armBufferTimer("stream stalled");
            });

            this.audio.addEventListener("ended", () =>
            {
                this.playPending = false;
                this.localEnded = true;
                this.clearBufferTimer();

                if(!this.desired.loop && this.hasIncompleteMedia())
                {
                    this.incomplete = true;
                    this.scheduleRetry("CDN stream ended before the full track was available");
                }
            });

            this.audio.addEventListener("error", () =>
            {
                this.playPending = false;

                const mediaError = this.audio.error;

                this.scheduleRetry(mediaError && (mediaError.message || `media error ${mediaError.code}`));
            });

            this.setSource(data.url, data.time || 0, false);
        }

        disconnect()
        {
            this.destroyed = true;
            this.clearBufferTimer();

            clearTimeout(this.retryTimer);

            this.audio.pause();
            this.audio.removeAttribute("src");
            this.audio.load();
            this.audio.remove(); // Fix Chromium CEF orphaned audio element bug

            for (const node of [this.source, this.panner, this.filter, this.compressor, this.gain, this.delay, this.feedback, this.wet])
            {
                if(node && typeof node.disconnect === "function")
                {
                    try
                    {
                        node.disconnect();
                    }
                    catch (_)
                    {
                    }
                }
            }
        }

        clearBufferTimer()
        {
            clearTimeout(this.bufferTimer);

            this.bufferTimer = null;
        }

        armBufferTimer(reason)
        {
            this.clearBufferTimer();

            if(this.destroyed || this.desired.paused || this.desired.ended)
            {
                return;
            }

            const timeout = Math.max(3000, Number(this.desired.bufferTimeoutMs) || 10000);
            
            this.bufferTimer = setTimeout(() =>
            {
                if(!this.destroyed && !this.desired.paused && this.audio.readyState < 3)
                {
                    this.scheduleRetry(reason);
                }
            }, timeout);
        }

        hasIncompleteMedia()
        {
            const expectedDuration = Number(this.desired.duration);
            const mediaDuration = Number(this.audio.duration);
            
            if(!Number.isFinite(expectedDuration) || expectedDuration <= 5)
            {
                return false;
            }
            
            if(!Number.isFinite(mediaDuration) || mediaDuration <= 0)
            {
                return false;
            }

            // High network/streaming latency or HTML5 Audio seeking can temporarily update
            // audio.duration before the full stream range header is resolved.
            // If the audio element is still downloading/buffering (seeking or readyState < 4),
            // do not mark it as incomplete.
            if(this.audio.seeking || (this.audio.readyState > 0 && this.audio.readyState < 4))
            {
                return false;
            }

            const tolerance = Math.max(15, expectedDuration * 0.10);
            return mediaDuration + tolerance < expectedDuration;
        }

        setSource(url, time, isRetry)
        {
            this.url = url;
            this.startTimeOffset = 0; // Luôn dùng 0 vì dùng seek trình duyệt
            this.ready = false;
            this.playPending = false;
            this.localEnded = false;
            this.incomplete = false;
            this.audio.src = isRetry ? retryUrl(url, this.retryCount) : url;
            this.pendingSeek = Number(time) || 0;
            this.audio.load();
            this.armBufferTimer("load timeout");
        }

        seek(time)
        {
            let target = Number(time);

            if(!Number.isFinite(target) || target < 0)
            {
                return;
            }

            const mediaDuration = Number(this.audio.duration);
            
            if(Number.isFinite(mediaDuration) && mediaDuration > 0 && !this.desired.loop)
            {
                target = Math.min(target, Math.max(0, mediaDuration - 0.05));
            }

            try
            {
                this.audio.currentTime = target;
                this.pendingSeek = null;
            }
            catch(err)
            {
                this.pendingSeek = target;
            }
        }

        syncTime(hard, allowBackward)
        {
            let target = Number(this.desired.time);

            if(!Number.isFinite(target) || target < 0 || this.desired.ended)
            {
                return;
            }

            if(!this.ready || this.audio.readyState < 1)
            {
                this.pendingSeek = target;
                return;
            }

            if(this.audio.seeking)
            {
                return;
            }

            const mediaDuration = Number(this.audio.duration);
            
            if(this.desired.loop && Number.isFinite(mediaDuration) && mediaDuration > 0)
            {
                target %= mediaDuration;
            }

            const delta = target - this.audio.currentTime;
            const difference = Math.abs(delta);
            const softThreshold = Math.max(0.2, Number(this.desired.softSyncThreshold) || 0.65);
            const hardThreshold = Math.max(2, Number(this.desired.hardSyncThreshold) || 6);

            if(hard || this.audio.paused || difference >= hardThreshold)
            {
                this.audio.playbackRate = 1;

                if(difference > 0.3)
                {
                    if(delta >= 0 || hard || this.audio.paused || allowBackward)
                    {
                        this.seek(target);
                    }
                    else
                    {
                        this.audio.playbackRate = 0.94;
                    }
                }
            }
            else if(difference > softThreshold)
            {
                this.audio.playbackRate = delta > 0 ? 1.04 : 0.96;
            }
            else if(difference < 0.25)
            {
                this.audio.playbackRate = 1;
            }
        }

        scheduleRetry(reason)
        {
            if(this.destroyed || this.desired.paused || this.desired.ended || this.retryTimer)
            {
                return;
            }

            this.clearBufferTimer();
            this.retryCount += 1;
            
            const maxRetries = Math.max(0, Number(this.desired.maxRetries) || 3);
            
            if(this.retryCount > maxRetries)
            {
                this.failed = true;
                
                reportError(this.id, reason || "audio could not be loaded", true);
                
                updateAudioLoadState(this.id, "error", "Không thể tải Audio này. Hãy thử bài hát khác hoặc thử lại");
                return;
            }

            const delay = Math.min(4000, 750 * (2 ** (this.retryCount - 1)));

            updateAudioLoadState(this.id, "buffering", `Đang thử tải lại Audio (${this.retryCount}/${maxRetries})...`);
            
            this.retryTimer = setTimeout(() =>
            {
                this.retryTimer = null;

                if(this.destroyed || this.desired.paused || this.desired.ended)
                {
                    return;
                }

                this.failed = false;
                this.audio.pause();
                this.setSource(this.url, this.desired.time || 0, true);
                this.tryPlay();
            }, delay);
        }

        reloadFailedSource()
        {
            clearTimeout(this.retryTimer);
            
            this.retryTimer = null;
            this.retryCount = 0;
            this.failed = false;
            this.setSource(this.url, this.desired.time || 0, true);
        }

        tryPlay()
        {
            if(this.destroyed || !this.ready || this.audio.readyState < 1 || this.failed || this.incomplete || this.localEnded || this.retryTimer || this.desired.paused || this.desired.ended || this.playPending)
            {
                return;
            }
            
            if(!this.audio.paused && !this.audio.ended)
            {
                return;
            }

            const startPlayback = () =>
            {
                if(this.destroyed || !this.ready || this.audio.readyState < 1 || this.failed || this.incomplete || this.localEnded || this.retryTimer || this.desired.paused || this.desired.ended || this.playPending)
                {
                    return;
                }
                
                this.playPending = true;

                let result;

                try
                {
                    result = this.audio.play();
                }
                catch(error)
                {
                    this.playPending = false;
                    this.scheduleRetry(error && error.message);
                    return;
                }

                Promise.resolve(result).then(() =>
                {
                    this.playPending = false;
                }).catch((error) =>
                {
                    this.playPending = false;

                    if(error && error.name === "NotAllowedError")
                    {
                        return;
                    }

                    this.scheduleRetry(error && error.message);
                });
            };

            const audioContext = context();

            if(audioContext && audioContext.state !== "running")
            {
                resumeContext().then(() =>
                {
                    if(audioContext.state === "running")
                    {
                        startPlayback();
                    }
                });
            }
            else
            {
                startPlayback();
            }
        }

        userSeek(time)
        {
            const target = Number(time);

            if(this.destroyed || !Number.isFinite(target) || target < 0)
            {
                return;
            }

            this.pendingUserSeek =
            {
                target,
                requestedAt: Date.now(),
                baseVersion: Number(this.desired.version) || 0,
                paused: !!this.desired.paused
            };
            this.desired =
            {
                ...this.desired,
                time: target,
                ended: false
            };
            this.localEnded = false;

            if(this.ready && this.audio.readyState >= 1)
            {
                this.seek(target);
            }
            else
            {
                this.pendingSeek = target;
            }

            if(!this.desired.paused)
            {
                this.tryPlay();
            }
        }

        apply(data)
        {
            this.audio.loop = !!data.loop;
            
            const effect = data.effect || {};
            const baseVolume = Math.max(0, Math.min(1, Number(data.volume ?? 0.75) * Number(effect.volumeMultiplier ?? 1)));
            const masterVolume = Math.max(0, Math.min(1, Number(data.masterVolume ?? 0.5)));
            const volume = baseVolume * masterVolume;
            const muffle = Math.max(0, Math.min(1, Number(effect.muffle ?? 0)));
            const echo = Math.max(0, Math.min(1, Number(effect.echo ?? 0)));

            if(this.usingGraph)
            {
                const position = data.position || {};
                const maxDistance = Math.max(1, Number(data.distance || 25));

                this.panner.maxDistance = maxDistance;
                this.panner.refDistance = Number(data.refDistance || 2);
                this.panner.rolloffFactor = Number(data.rolloffFactor || 1);

                const is2D = data.is2D !== undefined ? !!data.is2D : true;
                this.panner.panningModel = is2D ? "equalpower" : "HRTF";

                let px = Number(position.x || 0);
                let py = Number(position.y || 0);
                let pz = Number(position.z || 0);

                if(is2D && currentListenerData)
                {
                    const lx = Number(currentListenerData.x || 0);
                    const ly = Number(currentListenerData.y || 0);
                    const lz = Number(currentListenerData.z || 0);
                    const dx = px - lx;
                    const dy = py - ly;
                    const dz = pz - lz;
                    const dist = Math.sqrt(dx * dx + dy * dy + dz * dz);

                    const fx = Number(currentListenerData.forwardX || 0);
                    const fy = Number(currentListenerData.forwardY || 1);
                    const fz = Number(currentListenerData.forwardZ || 0);

                    px = lx + fx * dist;
                    py = ly + fy * dist;
                    pz = lz + fz * dist;
                }

                if(this.panner.positionX)
                {
                    setParam(this.panner.positionX, px, 0.02);
                    setParam(this.panner.positionY, py, 0.02);
                    setParam(this.panner.positionZ, pz, 0.02);
                }
                else
                {
                    this.panner.setPosition(px, py, pz);
                }

                setParam(this.gain.gain, volume);
                setParam(this.filter.frequency, 850 + ((1 - muffle) * 21150));
                setParam(this.filter.Q, 0.7 + (muffle * 1.4));
                setParam(this.wet.gain, echo * 0.32);
                setParam(this.feedback.gain, 0.12 + (echo * 0.22));
            }
            else
            {
                this.audio.volume = volume;
            }
        }

        start(data)
        {
            this.desired =
            {
                ...data
            };
            this.apply(data);

            if(data.paused)
            {
                this.audio.pause();
                return;
            }

            this.syncTime(true, true);
            this.tryPlay();
        }

        update(data)
        {
            const pendingSeek = this.pendingUserSeek;

            if(pendingSeek)
            {
                const elapsed = Math.max(0, (Date.now() - pendingSeek.requestedAt) / 1000);
                const expectedTime = pendingSeek.target + (pendingSeek.paused ? 0 : elapsed);
                const incomingTime = Number(data.time);
                const incomingVersion = Number(data.version) || 0;
                const acknowledged = incomingVersion > pendingSeek.baseVersion
                    && Number.isFinite(incomingTime)
                    && Math.abs(incomingTime - expectedTime) < 3;

                if(acknowledged || elapsed >= 4)
                {
                    this.pendingUserSeek = null;
                }
                else
                {
                    data =
                    {
                        ...data,
                        time: expectedTime,
                        ended: false
                    };
                }
            }

            const previousVersion = this.desired.version;
            const versionChanged = previousVersion !== data.version;
            const urlChanged = this.url !== data.url;

            this.desired =
            {
                ...this.desired,
                ...data
            };
            this.apply(data);

            if(urlChanged)
            {
                this.retryCount = 0;
                this.failed = false;
                this.setSource(data.url, data.time || 0, false);
            }
            else if(this.failed && versionChanged)
            {
                this.reloadFailedSource();
            }
            else if(this.localEnded && versionChanged && !data.ended)
            {
                this.setSource(data.url, data.time || 0, false);
            }

            this.syncTime(false, versionChanged);

            if(data.paused)
            {
                this.audio.pause();
                this.audio.playbackRate = 1;
                this.playPending = false;
            }
            else if(!data.ended)
            {
                this.tryPlay();

                if(versionChanged && !this.audio.paused)
                {
                    updateAudioLoadState(this.id, "playing", "Đang Phát");
                }
            }
        }
    }

    function play(data)
    {
        if(!data || !data.id || !data.url)
        {
            return;
        }
        
        const existing = items.get(data.id);
        
        if(existing && existing.url === data.url)
        {
            existing.update(data);
            return;
        }

        if(existing)
        {
            existing.disconnect();
        }

        const sound = new SpatialSound(data);
        
        items.set(data.id, sound);
        
        sound.start(data);
    }

    function update(data)
    {
        const sound = data && items.get(data.id);
        
        if(sound)
        {
            sound.update(data);
        }
        else
        {
            play(data);
        }
    }

    function destroy(data)
    {
        const id = data && data.id;
        const sound = items.get(id);

        if(!sound)
        {
            return;
        }

        sound.disconnect();
        
        items.delete(id);
    }

    function seekTo(id, time)
    {
        const sound = items.get(id);
        
        if(sound)
        {
            sound.userSeek(time);
        }
    }

    function listener(data)
    {
        const audioContext = context();
        
        if(!audioContext || !data || !data.listener)
        {
            return;
        }

        const listenerData = data.listener;
        currentListenerData = listenerData;
        const listenerNode = audioContext.listener;

        if(listenerNode.positionX)
        {
            setParam(listenerNode.positionX, Number(listenerData.x || 0), 0.02);
            setParam(listenerNode.positionY, Number(listenerData.y || 0), 0.02);
            setParam(listenerNode.positionZ, Number(listenerData.z || 0), 0.02);
            setParam(listenerNode.forwardX, Number(listenerData.forwardX || 0), 0.02);
            setParam(listenerNode.forwardY, Number(listenerData.forwardY || 1), 0.02);
            setParam(listenerNode.forwardZ, Number(listenerData.forwardZ || 0), 0.02);
            setParam(listenerNode.upX, Number(listenerData.upX || 0), 0.02);
            setParam(listenerNode.upY, Number(listenerData.upY || 0), 0.02);
            setParam(listenerNode.upZ, Number(listenerData.upZ || 1), 0.02);
        }
        else
        {
            listenerNode.setPosition(Number(listenerData.x || 0), Number(listenerData.y || 0), Number(listenerData.z || 0));
            listenerNode.setOrientation(
                Number(listenerData.forwardX || 0),
                Number(listenerData.forwardY || 1),
                Number(listenerData.forwardZ || 0),
                Number(listenerData.upX || 0),
                Number(listenerData.upY || 0),
                Number(listenerData.upZ || 1)
            );
        }

        for(const sound of items.values())
        {
            if(sound.desired && (sound.desired.is2D !== undefined ? sound.desired.is2D : true))
            {
                sound.apply(sound.desired);
            }
        }
    }
    return {
        play,
        update,
        destroy,
        seekTo,
        listener,
        unlock,
        items
    };
})();

window.addEventListener("message", (event) =>
{
    const data = event.data || {};

    if(data.app !== "lv_musicbox")
    {
        return;
    }

    if(data.action === "uiContext")
    {
        state.visible = !!data.visible;
        state.sources = Array.isArray(data.sources) ? data.sources : [];
        state.selectedSourceId = data.selectedSourceId || null;
        state.library = data.library ||
        {
            favorites: [],
            recent: []
        };
        state.strings = data.strings || {};
        
        render();
    }
    else if(data.action === "playStatus")
    {
        const phase = data.state === "loading"
            ? "resolving"
            : data.state === "resolved" ? "buffering" : "error";
        setPlayRequestPhase(phase, data.message, data);

        if(data.state === "error" && data.input)
        {
            markTrackAsDead(data.input);
        }
    }
    else if(data.action === "audioPlay")
    {
        AudioEngine.play(data);
    }
    else if(data.action === "audioUpdate")
    {
        AudioEngine.update(data);
    }
    else if(data.action === "audioDestroy")
    {
        AudioEngine.destroy(data);
    }
    else if(data.action === "audioListener")
    {
        AudioEngine.listener(data);
    }
});

window.addEventListener("DOMContentLoaded", () =>
{
    bindUi();

    render();

    post("ready");
});

// Periodic Progress bar and timer updates
setInterval(() =>
{
    if(!state.visible)
    {
        return;
    }

    const source = selectedSource();
    
    if(!source || !source.url)
    {
        if(!isDraggingProgress)
        {
            dom.playbackProgress.value = 0;
            dom.currentTime.textContent = "00:00";
            dom.totalTime.textContent = "00:00";
        }
        return;
    }

    const sound = AudioEngine.items.get(source.id);
    
    if(sound && sound.audio)
    {
        const audio = sound.audio;
        const isProxyStream = sound.url && sound.url.includes('/stream/');
        const offset = isProxyStream ? (sound.startTimeOffset || 0) : 0;
        const current = (audio.currentTime || 0) + offset;
        const duration = Number(source.duration) || 0;

        if(!isDraggingProgress)
        {
            if(duration > 0)
            {
                dom.playbackProgress.value = String(Math.floor((current / duration) * 100));
            }
            else
            {
                dom.playbackProgress.value = 0;
            }

            dom.currentTime.textContent = formatTime(current);
            dom.totalTime.textContent = duration > 0 ? formatTime(duration) : "--:--";
        }
    }
}, 500);

function formatTime(seconds)
{
    if(isNaN(seconds) || seconds === null)
    {
        return "00:00";
    }
    
    const mins = Math.floor(seconds / 60);
    const secs = Math.floor(seconds % 60);
    return `${String(mins).padStart(2, "0")}:${String(secs).padStart(2, "0")}`;
}
