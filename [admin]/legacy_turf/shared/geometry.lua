TurfGeometry = {}

local abs = math.abs
local max = math.max
local min = math.min
local sqrt = math.sqrt

local function finite(value)
    return type(value) == 'number' and value == value and value > -1000000.0 and value < 1000000.0
end

local function pointDistanceSquared(a, b)
    local dx = a.x - b.x
    local dy = a.y - b.y
    return dx * dx + dy * dy
end

local function orientation(a, b, c)
    return (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x)
end

local function onSegment(a, b, p)
    return p.x >= min(a.x, b.x) and p.x <= max(a.x, b.x)
        and p.y >= min(a.y, b.y) and p.y <= max(a.y, b.y)
        and abs(orientation(a, b, p)) < 0.00001
end

local function segmentsIntersect(a, b, c, d)
    local o1 = orientation(a, b, c)
    local o2 = orientation(a, b, d)
    local o3 = orientation(c, d, a)
    local o4 = orientation(c, d, b)

    if ((o1 > 0 and o2 < 0) or (o1 < 0 and o2 > 0))
        and ((o3 > 0 and o4 < 0) or (o3 < 0 and o4 > 0)) then
        return true
    end

    return (abs(o1) < 0.00001 and onSegment(a, b, c))
        or (abs(o2) < 0.00001 and onSegment(a, b, d))
        or (abs(o3) < 0.00001 and onSegment(c, d, a))
        or (abs(o4) < 0.00001 and onSegment(c, d, b))
end

function TurfGeometry.isFiniteNumber(value)
    return finite(value)
end

function TurfGeometry.normalizePoint(value)
    if type(value) ~= 'table' then return nil end

    local x = tonumber(value.x or value[1])
    local y = tonumber(value.y or value[2])
    local z = tonumber(value.z or value[3]) or 0.0
    if not finite(x) or not finite(y) or not finite(z) then return nil end

    return { x = x + 0.0, y = y + 0.0, z = z + 0.0 }
end

function TurfGeometry.polygonArea(points)
    local area = 0.0
    for i = 1, #points do
        local nextIndex = i == #points and 1 or i + 1
        area = area + points[i].x * points[nextIndex].y - points[nextIndex].x * points[i].y
    end
    return abs(area) * 0.5
end

function TurfGeometry.isSimplePolygon(points)
    local count = #points
    for i = 1, count do
        local iNext = i == count and 1 or i + 1
        for j = i + 1, count do
            local jNext = j == count and 1 or j + 1
            local adjacent = i == j or iNext == j or jNext == i
            if not adjacent and segmentsIntersect(points[i], points[iNext], points[j], points[jNext]) then
                return false
            end
        end
    end
    return true
end

function TurfGeometry.validatePolygon(rawPoints)
    if type(rawPoints) ~= 'table' then return nil, 'Danh sách điểm không hợp lệ.' end
    if #rawPoints < 3 then return nil, 'PolyZone cần ít nhất 3 điểm.' end
    if #rawPoints > Config.MaxPolygonPoints then
        return nil, ('PolyZone chỉ được tối đa %d điểm.'):format(Config.MaxPolygonPoints)
    end

    local points = {}
    local minimumDistanceSquared = Config.MinPointDistance * Config.MinPointDistance
    for i = 1, #rawPoints do
        local point = TurfGeometry.normalizePoint(rawPoints[i])
        if not point then return nil, ('Điểm thứ %d không hợp lệ.'):format(i) end

        for j = 1, #points do
            if pointDistanceSquared(point, points[j]) < minimumDistanceSquared then
                return nil, ('Điểm thứ %d quá gần một điểm đã có.'):format(i)
            end
        end
        points[#points + 1] = point
    end

    if TurfGeometry.polygonArea(points) < Config.MinPolygonArea then
        return nil, 'Diện tích PolyZone quá nhỏ.'
    end
    if not TurfGeometry.isSimplePolygon(points) then
        return nil, 'Các cạnh PolyZone đang cắt nhau.'
    end

    return points
end

function TurfGeometry.getCenter(zone)
    if zone.shape == 'circle' then
        return zone.center
    end

    local x, y, z = 0.0, 0.0, 0.0
    for i = 1, #(zone.points or {}) do
        x = x + zone.points[i].x
        y = y + zone.points[i].y
        z = z + (zone.points[i].z or 0.0)
    end
    local count = #(zone.points or {})
    if count == 0 then return { x = 0.0, y = 0.0, z = 0.0 } end
    return { x = x / count, y = y / count, z = z / count }
end

function TurfGeometry.getBoundingRadius(zone)
    if zone.shape == 'circle' then return zone.radius end
    local center = TurfGeometry.getCenter(zone)
    local radiusSquared = 0.0
    for i = 1, #(zone.points or {}) do
        radiusSquared = max(radiusSquared, pointDistanceSquared(center, zone.points[i]))
    end
    return sqrt(radiusSquared)
end

function TurfGeometry.contains(zone, coords)
    if not zone or not coords then return false end
    if zone.shape == 'circle' then
        local radius = tonumber(zone.radius) or 0.0
        return pointDistanceSquared(zone.center, coords) <= radius * radius
    end

    local points = zone.points or {}
    local inside = false
    local j = #points
    for i = 1, #points do
        local a = points[i]
        local b = points[j]
        local crosses = ((a.y > coords.y) ~= (b.y > coords.y))
            and (coords.x < (b.x - a.x) * (coords.y - a.y) / ((b.y - a.y) + 0.0) + a.x)
        if crosses then inside = not inside end
        j = i
    end
    return inside
end

local function nearestPointOnSegment(point, a, b)
    local dx = b.x - a.x
    local dy = b.y - a.y
    local lengthSquared = dx * dx + dy * dy
    if lengthSquared <= 0.00001 then return { x = a.x, y = a.y, z = a.z or point.z } end

    local t = ((point.x - a.x) * dx + (point.y - a.y) * dy) / lengthSquared
    t = max(0.0, min(1.0, t))
    return {
        x = a.x + t * dx,
        y = a.y + t * dy,
        z = (a.z or point.z) + t * ((b.z or point.z) - (a.z or point.z)),
    }
end

function TurfGeometry.nearestOutside(zone, coords, offset)
    offset = tonumber(offset) or 3.0
    local center = TurfGeometry.getCenter(zone)

    if zone.shape == 'circle' then
        local dx = coords.x - center.x
        local dy = coords.y - center.y
        local length = sqrt(dx * dx + dy * dy)
        if length < 0.001 then dx, dy, length = 1.0, 0.0, 1.0 end
        local distance = (tonumber(zone.radius) or 0.0) + offset
        return { x = center.x + dx / length * distance, y = center.y + dy / length * distance, z = coords.z }
    end

    local closest
    local closestDistanceSquared
    local points = zone.points or {}
    for i = 1, #points do
        local nextIndex = i == #points and 1 or i + 1
        local candidate = nearestPointOnSegment(coords, points[i], points[nextIndex])
        local distanceSquared = pointDistanceSquared(coords, candidate)
        if not closestDistanceSquared or distanceSquared < closestDistanceSquared then
            closest = candidate
            closestDistanceSquared = distanceSquared
        end
    end

    if not closest then return { x = coords.x, y = coords.y, z = coords.z } end
    local dx = closest.x - center.x
    local dy = closest.y - center.y
    local length = sqrt(dx * dx + dy * dy)
    if length < 0.001 then dx, dy, length = 1.0, 0.0, 1.0 end

    local result = {
        x = closest.x + dx / length * offset,
        y = closest.y + dy / length * offset,
        z = closest.z or coords.z,
    }
    if TurfGeometry.contains(zone, result) then
        result.x = closest.x + dx / length * (offset * 2.0)
        result.y = closest.y + dy / length * (offset * 2.0)
    end
    return result
end

