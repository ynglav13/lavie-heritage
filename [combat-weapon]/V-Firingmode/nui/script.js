window.addEventListener('message', function(event)
{
    const item = event.data;
    const container = document.getElementById('container');
    const textDiv = document.getElementById('text');

    if(item.action === 'update')
    {
        if(item.text)
        {
            let formatted = item.text
                .replace(/~y~/g, '<span class="yellow">')
                .replace(/~w~/g, '</span><span class="white">');
            
            if(!formatted.startsWith('<span'))
            {
                formatted = '<span class="white">' + formatted + '</span>';
            }
            else
            {
                formatted += '</span>';
            }

            textDiv.innerHTML = formatted;
            container.style.display = 'block';
        }
    }
    else if(item.action === 'hide')
    {
        container.style.display = 'none';
    }
});