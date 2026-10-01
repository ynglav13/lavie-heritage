(() =>
{
    const root = document.getElementById('notify-root');
    const stacks = new Map();
    const fallbackTypes =
    {
        info:
        {
            icon: 'info',
            accent: '#60a5fa'
        },
        success:
        {
            icon: 'success',
            accent: '#34d399'
        },
        warning:
        {
            icon: 'warning',
            accent: '#fbbf24'
        },
        error:
        {
            icon: 'error',
            accent: '#fb7185'
        },
        police:
        {
            icon: 'police',
            accent: '#38bdf8'
        },
        ambulance:
        {
            icon: 'ambulance',
            accent: '#f87171'
        },
        money:
        {
            icon: 'money',
            accent: '#4ade80'
        }
    };

    const icons =
    {
        info: '<svg viewBox="0 0 24 24" aria-hidden="true"><circle cx="12" cy="12" r="9"></circle><path d="M12 10v6"></path><path d="M12 7.5h.01"></path></svg>',
        success: '<svg viewBox="0 0 24 24" aria-hidden="true"><circle cx="12" cy="12" r="9"></circle><path d="m8.5 12.4 2.3 2.3 4.9-5.2"></path></svg>',
        warning: '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M10.4 4.8 3.2 17.2A2 2 0 0 0 5 20h14a2 2 0 0 0 1.8-2.8L13.6 4.8a1.8 1.8 0 0 0-3.2 0Z"></path><path d="M12 9v4"></path><path d="M12 16.5h.01"></path></svg>',
        error: '<svg viewBox="0 0 24 24" aria-hidden="true"><circle cx="12" cy="12" r="9"></circle><path d="m9 9 6 6"></path><path d="m15 9-6 6"></path></svg>',
        police: '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M12 3 5.5 5.5v5.2c0 4.2 2.6 7.9 6.5 9.3 3.9-1.4 6.5-5.1 6.5-9.3V5.5L12 3Z"></path><path d="M9 11.5h6"></path><path d="M12 8.5v6"></path></svg>',
        ambulance: '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M4 7h10v9H4z"></path><path d="M14 10h3l3 3v3h-6z"></path><path d="M8 7v9"></path><path d="M5.5 11.5h5"></path><circle cx="7" cy="18" r="1.5"></circle><circle cx="17" cy="18" r="1.5"></circle></svg>',
        money: '<svg viewBox="0 0 24 24" aria-hidden="true"><rect x="3.5" y="6.5" width="17" height="11" rx="2"></rect><circle cx="12" cy="12" r="2.5"></circle><path d="M6.5 9.5v.01"></path><path d="M17.5 14.5v.01"></path></svg>',
        vip: '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="m4 8 4.2 3.2L12 5l3.8 6.2L20 8l-1.7 10H5.7L4 8Z"></path><path d="M7 18h10"></path></svg>',
        phone: '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M22 16.92v3a2 2 0 0 1-2.18 2 19.79 19.79 0 0 1-8.63-3.07 19.5 19.5 0 0 1-6-6 19.79 19.79 0 0 1-3.07-8.67A2 2 0 0 1 4.11 2h3a2 2 0 0 1 2 1.72 12.84 12.84 0 0 0 .7 2.81 2 2 0 0 1-.45 2.11L8.09 9.91a16 16 0 0 0 6 6l1.27-1.27a2 2 0 0 1 2.11-.45 12.84 12.84 0 0 0 2.81.7A2 2 0 0 1 22 16.92z"></path></svg>'
    };

    const positions = new Set(
    [
        'top-right',
        'top-left',
        'top-center',
        'bottom-right',
        'bottom-left',
        'bottom-center',
        'middle-right',
        'middle-left'
    ]);

    function getStack(position)
    {
        const safePosition = positions.has(position) ? position : 'top-right';

        if(stacks.has(safePosition))
        {
            return stacks.get(safePosition);
        }

        const stack = document.createElement('div');

        stack.className = `notify-stack ${safePosition}`;

        root.appendChild(stack);

        stacks.set(safePosition, stack);
        return stack;
    }

    function text(value, fallback)
    {
        if(value === undefined || value === null)
        {
            return fallback;
        }

        const next = String(value).trim();
        return next || fallback;
    }

    function setIcon(element, icon, type)
    {
        const key = text(icon, type).toLowerCase();
        const normalized =
        {
            i: 'info',
            ok: 'success',
            check: 'success',
            '!': 'warning',
            warn: 'warning',
            x: 'error',
            pd: 'police',
            ems: 'ambulance',
            '+': 'ambulance',
            '$': 'money',
            cash: 'money',
            prime: 'vip',
            call: 'phone'
        }

        [key] || key;

        if(icons[normalized])
        {
            element.innerHTML = icons[normalized];
            return;
        }

        if(icons[type])
        {
            element.innerHTML = icons[type];
            return;
        }

        element.innerHTML = icons.info;
    }

    function removeNotification(element)
    {
        if(!element || element.dataset.removing === 'true')
        {
            return;
        }

        element.dataset.removing = 'true';
        element.classList.remove('show');
        element.classList.add('hide');

        window.setTimeout(() =>
        {
            element.remove();
        }, 220);
    }

    function enforceLimit(stack, limit)
    {
        const maxVisible = Number.isFinite(limit) ? limit : 5;
        const items = Array.from(stack.querySelectorAll('.lv-notify'));

        while(items.length > maxVisible)
        {
            const oldest = items.shift();
            removeNotification(oldest);
        }
    }

    function notify(data)
    {
        const payload = data || {};
        const type = text(payload.type, 'info').toLowerCase();
        const fallback = fallbackTypes[type] || fallbackTypes.info;
        const duration = Math.min(Math.max(Number(payload.duration) || 3600, 1200), 30000);
        const stack = getStack(text(payload.position, 'top-right').toLowerCase());
        const element = document.createElement('article');
        const icon = text(payload.icon, fallback.icon);
        const title = text(payload.title, 'Lavie');
        const message = text(payload.message, 'Thông Báo Mới');
        const accent = text(payload.accent, fallback.accent);

        element.className = `lv-notify lv-notify--${type}`;
        element.style.setProperty('--accent', accent);
        element.innerHTML = `
            <div class="lv-notify__icon"></div>
            <div class="lv-notify__content">
                <h3 class="lv-notify__title"></h3>
                <p class="lv-notify__message"></p>
            </div>
            <div class="lv-notify__bar"><span></span></div>
        `;

        setIcon(element.querySelector('.lv-notify__icon'), icon, type);

        element.querySelector('.lv-notify__title').textContent = title;
        element.querySelector('.lv-notify__message').textContent = message;
        element.querySelector('.lv-notify__bar span').style.animationDuration = `${duration}ms`;

        if(stack.classList.contains('bottom-right') || stack.classList.contains('bottom-left') || stack.classList.contains('bottom-center'))
        {
            stack.prepend(element);
        }
        else
        {
            stack.appendChild(element);
        }

        window.requestAnimationFrame(() =>
        {
            element.classList.add('show');
        });

        enforceLimit(stack, Number(payload.maxVisible));

        window.setTimeout(() => removeNotification(element), duration);
    }

    const confirmModal = document.getElementById('confirm-modal');
    const confirmTitle = document.getElementById('modal-title');
    const confirmMessage = document.getElementById('modal-message');
    const confirmYes = document.getElementById('confirm-yes');
    const confirmNo = document.getElementById('confirm-no');

    function showConfirm(payload)
    {
        confirmTitle.textContent = payload.title || 'Xác nhận';
        confirmMessage.textContent = payload.message || 'Bạn có chắc chắn không?';
        confirmYes.textContent = payload.yesLabel || 'Đồng ý';
        confirmNo.textContent = payload.noLabel || 'Từ chối';

        confirmModal.style.display = 'flex';

        window.requestAnimationFrame(() =>
        {
            confirmModal.classList.add('show');
        });
    }

    function closeConfirm(status)
    {
        confirmModal.classList.remove('show');

        window.setTimeout(() =>
        {
            confirmModal.style.display = 'none';

            fetch(`https://${GetParentResourceName()}/confirm_callback`,
            {
                method: 'POST',
                headers:
                {
                    'Content-Type': 'application/json; charset=UTF-8',
                },
                body: JSON.stringify(
                {
                    status: status
                })
            }).catch(err => console.error(err));
        }, 200);
    }

    confirmYes.addEventListener('click', () => closeConfirm(true));
    confirmNo.addEventListener('click', () => closeConfirm(false));

    window.addEventListener('message', (event) =>
    {
        if(!event.data)
        {
            return;
        }

        if(event.data.action === 'notify')
        {
            notify(event.data.data);
        }
        else if (event.data.action === 'confirm')
        {
            showConfirm(event.data.data);
        }
    });
})();