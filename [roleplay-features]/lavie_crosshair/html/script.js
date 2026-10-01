window.addEventListener('message', function(event) {
    const data = event.data;

    if (data.action === "updateVisibility") {
        const container = document.getElementById('crosshair-container');
        if (data.visible) {
            container.style.display = 'flex';
        } else {
            container.style.display = 'none';
        }
    } else if (data.action === "updateSettings") {
        updateCrosshair(data.settings);
    }
});

function updateCrosshair(settings) {
    const svg = document.getElementById('crosshair-svg');
    svg.innerHTML = ''; // Clear previous elements

    if (!settings || !settings.type) return;

    // Convert values (multiply by 1000 since viewBox is -50 to 50, scale is relative to 10vh SVG box)
    // 10vh SVG box = 10% of screen height.
    // Config size 0.0038 = 0.38% of screen height = 3.8 units out of 1000.
    // SVG viewBox height is 100 (from -50 to 50), so a config size of 0.0038 is 3.8 units in the viewBox coordinate system.
    const size = (settings.size || 0.0038) * 1000;
    const thickness = (settings.thickness || 0.0015) * 1000;
    const gap = (settings.gap || 0) * 1000;
    const dotSize = (settings.dotSize || 0.002) * 1000;

    const r = settings.color[0];
    const g = settings.color[1];
    const b = settings.color[2];
    const a = (settings.color[3] || 255) / 255;
    const color = `rgba(${r}, ${g}, ${b}, ${a})`;

    const or = settings.outlineColor ? settings.outlineColor[0] : 0;
    const og = settings.outlineColor ? settings.outlineColor[1] : 0;
    const ob = settings.outlineColor ? settings.outlineColor[2] : 0;
    const oa = settings.outlineColor ? (settings.outlineColor[3] || 255) / 255 : 1.0;
    const outlineColor = `rgba(${or}, ${og}, ${ob}, ${oa})`;
    const outline = settings.outline;
    const outlineWidth = settings.outlineWidth !== undefined ? settings.outlineWidth : 0.8; // thickness of outline stroke edge

    const drawOutline = (el) => {
        if (!outline) return;
        const clone = el.cloneNode(true);
        if (clone.getAttribute('stroke') && clone.getAttribute('stroke') !== 'none') {
            const currentStrokeWidth = parseFloat(clone.getAttribute('stroke-width') || 0);
            clone.setAttribute('stroke', outlineColor);
            clone.setAttribute('stroke-width', currentStrokeWidth + outlineWidth * 2);
        } else if (clone.getAttribute('fill') && clone.getAttribute('fill') !== 'none') {
            clone.setAttribute('stroke', outlineColor);
            clone.setAttribute('stroke-width', outlineWidth * 2);
            // If the element has a fill, we stroke the outer edge or make the fill itself outlineColor
            clone.setAttribute('fill', outlineColor);
        }
        svg.appendChild(clone);
    };

    const drawElement = (el) => {
        svg.appendChild(el);
    };

    const createLine = (x1, y1, x2, y2) => {
        const line = document.createElementNS('http://www.w3.org/2000/svg', 'line');
        line.setAttribute('x1', x1);
        line.setAttribute('y1', y1);
        line.setAttribute('x2', x2);
        line.setAttribute('y2', y2);
        line.setAttribute('stroke', color);
        line.setAttribute('stroke-width', thickness);
        line.setAttribute('stroke-linecap', 'square');
        return line;
    };

    const createCircle = (cx, cy, r, fill, stroke, strokeWidth) => {
        const circle = document.createElementNS('http://www.w3.org/2000/svg', 'circle');
        circle.setAttribute('cx', cx);
        circle.setAttribute('cy', cy);
        circle.setAttribute('r', r);
        circle.setAttribute('fill', fill || 'none');
        if (stroke) {
            circle.setAttribute('stroke', stroke);
            circle.setAttribute('stroke-width', strokeWidth || thickness);
        }
        return circle;
    };

    const elementsToDraw = [];

    switch(settings.type) {
        case 'cross':
            elementsToDraw.push(createLine(0, -gap - size, 0, -gap)); // Top
            elementsToDraw.push(createLine(0, gap, 0, gap + size));   // Bottom
            elementsToDraw.push(createLine(-gap - size, 0, -gap, 0)); // Left
            elementsToDraw.push(createLine(gap, 0, gap + size, 0));   // Right
            break;

        case 'dot':
            elementsToDraw.push(createCircle(0, 0, dotSize / 2, color, null, null));
            break;

        case 'cross_dot':
            // Dot
            elementsToDraw.push(createCircle(0, 0, dotSize / 2, color, null, null));
            // Cross
            elementsToDraw.push(createLine(0, -gap - size, 0, -gap));
            elementsToDraw.push(createLine(0, gap, 0, gap + size));
            elementsToDraw.push(createLine(-gap - size, 0, -gap, 0));
            elementsToDraw.push(createLine(gap, 0, gap + size, 0));
            break;

        case 'circle':
            elementsToDraw.push(createCircle(0, 0, size * (settings.radius || 0.6), 'none', color, thickness));
            break;

        case 'circle_cross':
            // Circle
            elementsToDraw.push(createCircle(0, 0, size * (settings.radius || 0.6), 'none', color, thickness));
            // Cross
            elementsToDraw.push(createLine(0, -gap - size, 0, -gap));
            elementsToDraw.push(createLine(0, gap, 0, gap + size));
            elementsToDraw.push(createLine(-gap - size, 0, -gap, 0));
            elementsToDraw.push(createLine(gap, 0, gap + size, 0));
            break;


        case 'diamond':
            const poly = document.createElementNS('http://www.w3.org/2000/svg', 'polygon');
            const s = size * 0.6;
            poly.setAttribute('points', `0,${-s} ${s},0 0,${s} ${-s},0`);
            poly.setAttribute('fill', 'none');
            poly.setAttribute('stroke', color);
            poly.setAttribute('stroke-width', thickness);
            elementsToDraw.push(poly);
            break;

        case 'arrows':
            const len = size * 0.6;
            const arrowSize = size * 0.3;
            const aGap = gap + size * 0.1;
            const as = arrowSize * 0.5;

            // Draw chevrons/arrows
            // Top pointing down
            const topChevron = document.createElementNS('http://www.w3.org/2000/svg', 'polyline');
            topChevron.setAttribute('points', `${-as},${-aGap - as} 0,${-aGap} ${as},${-aGap - as}`);
            topChevron.setAttribute('fill', 'none');
            topChevron.setAttribute('stroke', color);
            topChevron.setAttribute('stroke-width', thickness);
            elementsToDraw.push(topChevron);

            // Bottom pointing up
            const bottomChevron = document.createElementNS('http://www.w3.org/2000/svg', 'polyline');
            bottomChevron.setAttribute('points', `${-as},${aGap + as} 0,${aGap} ${as},${aGap + as}`);
            bottomChevron.setAttribute('fill', 'none');
            bottomChevron.setAttribute('stroke', color);
            bottomChevron.setAttribute('stroke-width', thickness);
            elementsToDraw.push(bottomChevron);

            // Left pointing right
            const leftChevron = document.createElementNS('http://www.w3.org/2000/svg', 'polyline');
            leftChevron.setAttribute('points', `${-aGap - as},${-as} ${-aGap},0 ${-aGap - as},${as}`);
            leftChevron.setAttribute('fill', 'none');
            leftChevron.setAttribute('stroke', color);
            leftChevron.setAttribute('stroke-width', thickness);
            elementsToDraw.push(leftChevron);

            // Right pointing left
            const rightChevron = document.createElementNS('http://www.w3.org/2000/svg', 'polyline');
            rightChevron.setAttribute('points', `${aGap + as},${-as} ${aGap},0 ${aGap + as},${as}`);
            rightChevron.setAttribute('fill', 'none');
            rightChevron.setAttribute('stroke', color);
            rightChevron.setAttribute('stroke-width', thickness);
            elementsToDraw.push(rightChevron);
            break;
    }

    // Render outlines first so they appear behind/under the main elements
    elementsToDraw.forEach(drawOutline);
    // Render main elements on top
    elementsToDraw.forEach(drawElement);
}
