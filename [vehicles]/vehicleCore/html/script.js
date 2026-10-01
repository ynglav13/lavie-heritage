const container = document.getElementById('hologram-container');
const panel = document.getElementById('lock-panel');
const icon = document.getElementById('lock-icon');
const title = document.getElementById('lock-title');
const desc = document.getElementById('lock-desc');
const crashEffectAudio = document.getElementById('crash-effect-audio');

let hideTimeout;

window.addEventListener('message', function (event)
{
    const data = event.data;

    if(data.action === 'PLAY_CRASH_SOUND')
    {
        const requestedVolume = Number(data.volume);
        const volume = Number.isFinite(requestedVolume)
            ? Math.min(1, Math.max(0, requestedVolume))
            : 0.15;

        crashEffectAudio.pause();
        crashEffectAudio.currentTime = 0;
        crashEffectAudio.volume = volume;
        crashEffectAudio.play().catch(() => {});
    }
    else if(data.action === 'STOP_CRASH_SOUND')
    {
        crashEffectAudio.pause();
        crashEffectAudio.currentTime = 0;
    }
    else if(data.action === 'SHOW_LOCK_UI')
    {
        const isLocked = data.status === 'locked';

        // Update classes
        panel.className = 'toast-panel'; // Reset
        panel.classList.add(isLocked ? 'locked' : 'unlocked');

        // Update Icon
        icon.className = isLocked ? 'fa-solid fa-lock' : 'fa-solid fa-lock-open';

        // Update Text
        title.innerText = isLocked ? 'VEHICLE LOCKED' : 'VEHICLE UNLOCKED';
        desc.innerText = isLocked ? 'Phương tiện của bạn đã được khoá' : 'Phương tiện của bạn đã được mở khoá';

        // Reset animation by triggering reflow
        panel.style.animation = 'none';
        panel.offsetHeight; /* trigger reflow */
        panel.style.animation = null;

        // Show UI
        container.classList.remove('hidden');
        container.style.opacity = '';

        // Clear previous timeout if exists
        if (hideTimeout) clearTimeout(hideTimeout);

        // Hide after 2 seconds
        hideTimeout = setTimeout(() =>
        {
            container.classList.add('hidden');
        }, 2000);

    }
    else if (data.action === 'UPDATE_COORDS')
    {
        const screenX = data.x * 100;
        const screenY = data.y * 100;

        if(data.x < 0 || data.x > 1 || data.y < 0 || data.y > 1)
        {
            container.style.opacity = '0';
        }
        else
        {
            // Use transform instead of left/top for 60FPS GPU acceleration
            container.style.transform = `translate3d(calc(${screenX}vw - 50%), calc(${screenY}vh - 50%), 0)`;
            
            if(!container.classList.contains('hidden'))
            {
                container.style.opacity = '';
            }
        }
    }
});
