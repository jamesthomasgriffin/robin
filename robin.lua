--- Raster of Bezier Intersection NeighbourHeightoods (ROBIN)
-- @module robin
-- @author James Griffin
-- @license MIT

local pixelShaderPath = "robin-pixel.glsl"
local vertexShaderPath = "robin-vertex.glsl"


-- @param s an array of 6 floats defining a quadratic Bezier segment
-- @return floats xMin, xMax, yMin, yMax
local function segmentBounds(s)
  return math.min(s[1], s[3], s[5]), math.max(s[1], s[3], s[5]),
    math.min(s[2], s[4], s[6]), math.max(s[2], s[4], s[6])
end

local function expandBounds(b, xMin, xMax, yMin, yMax)
  b[1] = math.min(b[1], xMin)
  b[2] = math.max(b[2], xMax)
  b[3] = math.min(b[3], yMin)
  b[4] = math.max(b[4], yMax)
  return b
end

--- Interprets a more general curve solely in terms of quadratic Beziers.
-- @param curve a list of lines, quadratic and cubic Beziers defined by arrays of
-- 4, 6 and 8 numbers respectively.
-- @param f a function that takes a quadratic segment and transforms it in place,
-- nil is interpreted as a trivial function that does nothing.
-- @return generating function representing a view of the curve with only 
-- quadratic Bezier segments.  For each jump between components of the curve
-- an extra segment is added. The generating function returns index, segment, 
-- shouldSkip, the third value indicates that the segment is a jump.
local function wrangledVersion(curve, f)
  local curveIndex = 0
  local index = 0
  local outSegment = { 0, 0, 0, 0, 0, 0 }
  local bankedSegment = {}
  local cursor = {}
  
  return function()
    local shouldSkip = false
    if #bankedSegment > 0 then
      for i = 1, 6 do 
        outSegment[i] = bankedSegment[i]
        bankedSegment[i] = nil
      end
    else
      curveIndex = curveIndex + 1
      local segment = curve[curveIndex]
      if not segment then return end
      
      if (#cursor > 0) and not (cursor[1] == segment[1] and cursor[2] == segment[2]) then
        outSegment[1], outSegment[2] = cursor[1], cursor[2]
        outSegment[5], outSegment[6] = segment[1], segment[2]
        curveIndex = curveIndex - 1
        shouldSkip = true
      elseif #segment == 4 then
        local ax, ay, bx, by = unpack(segment)
        outSegment[1], outSegment[2] = ax, ay
        outSegment[3], outSegment[4] = (ax+bx)/2, (ay+by)/2
        outSegment[5], outSegment[6] = bx, by      
      elseif #segment == 6 then
        for i = 1, 6 do
          outSegment[i] = segment[i]
        end      
      elseif #segment == 8 then
        local s = segment
        local function l(i, j, t) return s[i] * (1 - t) + s[j] * t end
        local ax, ay = l(1,3,0.75), l(2,4,0.75)
        local bx, by = l(5,7,0.25), l(6,8,0.25)
        local cx, cy = (ax + bx)/2, (ay + by) / 2
        outSegment[1], outSegment[2] = s[1], s[2]
        outSegment[3], outSegment[4] = ax, ay
        outSegment[5], outSegment[6] = cx, cy
        bankedSegment[1], bankedSegment[2] = cx, cy
        bankedSegment[3], bankedSegment[4] = bx, by
        bankedSegment[5], bankedSegment[6] = s[7], s[8]      
      else error("Unexpected segment of size "..#segment) end      
    end
    cursor[1], cursor[2] = outSegment[5], outSegment[6]
    index = index + 1
    if f then f(outSegment) end
    return index, outSegment, shouldSkip
  end
end

--- A class that does the work of computing intersections
-- it's essentially a 1D quadratic Bezier, or equivalently a quadratic function 
-- defined using basis elements t^2, 2t(1-t), (1-t)^2.
local BernsteinQuadratic = {}
BernsteinQuadratic.__index = BernsteinQuadratic

function BernsteinQuadratic.new(p1, p2, p3)
  return setmetatable({p1, p2, p3}, BernsteinQuadratic)
end

function BernsteinQuadratic:eval(t)
  -- u^2 p1 + 2ut p2 + t^2 p3 = u(u p1 + t p2) + t(u p2 + t p3)
  local u = 1 - t
  local a = self[1] * u + self[2] * t
  local b = self[2] * u + self[3] * t
  return a * u + b * t
end

function BernsteinQuadratic:stationaryPoint()
  --(p1 - 2p2 + p3) t - (p1 - p2) = 0
  local q = self[1] - 2*self[2] + self[3]
  local p = self[1] - self[2]
  if math.abs(q) > 1e-9 then
    return p / q
  end
end

--- Solves the equation y(t) = n where n is any integer and t is in [0, 1] 
-- Has an additional condition for the endpoints: TODO, which 
-- guarantees that in a piecewise quadratic curve proper crossings are not
-- double counted, and so guarantees that winding number calculations are correct.
-- returns a sorted list of { t, y, parity } crossing records.
function BernsteinQuadratic:integerIntersections()

  local EPSILON = 1e-9
  local p1, p2, p3 = self[1], self[2], self[3]
  
  -- This is same lookup table used in the pixel shader, the first boolean
  -- returned determines if the first (negative parity) root (-b - sqrt(d)) / 2a 
  -- is a solution, the second determines when the second (positive parity)
  -- root (-b + sqrt(d)) / 2a is a solution.
  local rootLUT = { false, false, true, false, true, true, true, false }
  local function rootTypes(n)
    local index = 1 +
      (p1 < n and 1 or 0) +
      (p2 < n and 2 or 0) +
      (p3 < n and 4 or 0)
    return rootLUT[index], rootLUT[9 - index]
  end
  
  -- polynomial coefficients, A t^2 + B t + C
  local A = p1 - 2*p2 + p3
  local B = 2*(p2 - p1)
  local C = p1
  
  local function roots(n)
    if math.abs(A) < EPSILON then -- solve Bt + C = n
      if math.abs(B) < EPSILON then
        return
      end
      local t = (n - C) / B
      return t, t -- this is not a double root, exactly one of these will be used
    end
    local D = B * B - 4 * A * (C - n)
    local sqrtD = math.sqrt(math.max(D, 0))
    return (-B - sqrtD) / (2 * A), (-B + sqrtD) / (2 * A)
  end  
  
  local function range()
    local yMin, yMax = math.min(p1, p3), math.max(p1, p3)
    if math.abs(A) > EPSILON then
      local tStat = -B / (2*A)
      if tStat > 0 and tStat < 1 then
        local yStat = self:eval(tStat)
        yMin = math.min(yMin, yStat)
        yMax = math.max(yMax, yStat)
      end
    end
    return yMin, yMax
  end
  
  local yMin, yMax = range()
  
  local nLow = math.ceil(yMin)
  local nHigh = math.floor(yMax)

  local results = {}

  for n = nLow, nHigh do
    local t1, t2 = roots(n)
    local c1, c2 = rootTypes(n)
    
    if c1 and c2 and t1 == t2 then
      -- either no root or a double root, skip it
      -- TODO, is this correct for the degenerate linear case?
    else
      if c1 then
        table.insert(results, {t = t1, y = n, parity = -1})
      end
      if c2 then
        table.insert(results, {t = t2, y = n, parity = 1})
      end
    end
  end

  table.sort(results, function(a, b) return a.t < b.t end)
    
  return results
end

local function closeToInteger(a)
  return math.abs(a - math.floor(a + 0.5)) < 1e-5
end
local nudgeDistance = 3e-5

-- returns an array of rows, each row is an array of pixels. Each pixel 
-- records the indices of the segments that pass through it and a partial
-- computation of the winding number for the remaining segments not passing 
-- through it.
local function getPixelIntersections(curve, numColumns, numRows, transform)
  transform = transform or {1, 1, 0, 0}
  local ax, ay, bx, by = unpack(transform)
  
  local function transformThenNudge(s)
    for i=2,6,2 do
      s[i-1] = ax * s[i-1] + bx
      s[i] = ay * s[i] + by
      if closeToInteger(s[i]) then
        s[i] = s[i] + nudgeDistance
      end
    end
  end
  
  local res = {}
  for y = 1, numRows do
    local row = {}
    res[y] = row
    for x = 1, numColumns do
      row[x] = { windingNo = 0 }
    end
  end
    
  for index, s, shouldSkip in wrangledVersion(curve, transformThenNudge) do
  
    if not shouldSkip then
      local sx = BernsteinQuadratic.new(s[1], s[3], s[5])
      local sy = BernsteinQuadratic.new(s[2], s[4], s[6])
      
      local intersections = sy:integerIntersections()
      
      local stationaryT = sx:stationaryPoint()
      local stationaryValue = stationaryT and sx:eval(stationaryT)
      
      local function addIntersections(row, tBegin, tEnd)
        local xBegin, xEnd = sx:eval(tBegin), sx:eval(tEnd)
        local xMin = math.min(xBegin, xEnd)
        local xMax = math.max(xBegin, xEnd)
        if stationaryT and stationaryT > tBegin and stationaryT < tEnd then
          xMin = math.min(xMin, stationaryValue)
          xMax = math.max(xMax, stationaryValue)
        end
        local m, M = math.floor(xMin), math.floor(xMax)        
        for n = math.max(m, 0), math.min(M, #row-1) do
          local pixel = row[n+1]
          if pixel[#pixel] ~= index then
            table.insert(pixel, index)
          end
        end
      end
      
      for i = 0, #intersections do
        local rowIndex, tBegin, tEnd
        if i == 0 then
          rowIndex = math.floor(sy:eval(0))
          tBegin = 0
          tEnd = (#intersections == 0) and 1 or intersections[1].t
        else          
          local intn = intersections[i]
          rowIndex = (intn.parity == 1) and intn.y or (intn.y - 1)
          tBegin = intn.t
          tEnd = (i == #intersections) and 1 or intersections[i+1].t
        end
        local row = res[rowIndex+1]
        if row then
          addIntersections(row, tBegin, tEnd)
        end
      end      
      
      for _, intn in ipairs(intersections) do
        local row = res[intn.y+1]
        if row then
          local x = sx:eval(intn.t)
          for i = math.max(math.ceil(x)+1, 1), numColumns do
            local cell = row[i]
            if cell[#cell] ~= index then
              cell.windingNo = cell.windingNo + intn.parity
            end
          end
        end
      end
    end
  end 
  return res  
end

--- tests whether a sorted list contains all integers between its minimum and
-- maximum values
-- @param t a sorted list
-- @return boolean
local function isContiguous(t)
  for i = 2, #t do
    local diff = t[i] - t[i-1]
    if not (diff == 0 or diff == 1) then
      return false
    end
  end
  return true
end

local BYTES_PER_FLOAT = 4
local FLOATS_PER_SEGMENT = 4 -- not 6 as end of one segment is the start of the next
local FLOATS_PER_FULL_SEGMENT = 6
local BYTES_PER_SEGMENT = BYTES_PER_FLOAT * FLOATS_PER_SEGMENT
local BYTES_PER_FULL_SEGMENT = BYTES_PER_FLOAT * FLOATS_PER_FULL_SEGMENT
  
local function copyCurveToBlob(curve, buffer, f)

  local curveStart = {curve[1][1], curve[1][2]}
  f(curveStart)
  local segmentCount = 0
  for ix, seg, shouldSkip in wrangledVersion(curve, f) do
    if shouldSkip then
      curveStart[1], curveStart[2] = seg[5], seg[6]
    end
    buffer:setF32(BYTES_PER_SEGMENT * segmentCount, seg[1], seg[2], seg[3], seg[4])
    segmentCount = segmentCount + 1
  end
  
  -- This extra data provides the endpoint of the final segment
  buffer:setF32(BYTES_PER_SEGMENT * segmentCount, curveStart[1], curveStart[2], 0, 0)
  segmentCount = segmentCount + 1
  
  return segmentCount
end

local function composeTransform(a, b)
  return { a[1] * b[1], a[2] * b[2], a[3] + a[1] * b[3], a[4] + a[2] * b[4] }
end

local function invertTransform(a)
  return { 1 / a[1], 1 / a[2], -a[3] / a[1], -a[4] / a[2] }
end

--- 
-- @param array of segments, each segment is an array of numbers
-- * 4 for a line
-- * 6 for a quadratic Bezier
--
-- @param Image of type 'rg16' for the output raster
-- @param Blob for the output float data
-- @param array of 4 numbers representing an affine transform
--
-- @return table of properties required for rendering:
-- TODO describe these properties
local function prepareCurve(curve, raster, buffer, bounds)
  if #curve == 0 then error("Curve must not be empty") end
  
  if not bounds then  
    bounds = {math.huge, -math.huge, math.huge, -math.huge}
    for _, seg in wrangledVersion(curve) do
      expandBounds(bounds, segmentBounds(seg))
    end
  end
  
  local numColumns, numRows = raster:getDimensions()
  local uvToRaster = {numColumns, numRows, 0, 0}

  local uvToCurve = {bounds[2] - bounds[1], bounds[4] - bounds[3], bounds[1], bounds[3]}  
  local curveToUV = invertTransform(uvToCurve)
  local curveToRaster = composeTransform(uvToRaster, curveToUV)
  
  local function nudge(s)
    local a, b = curveToRaster[2], curveToRaster[4]
    for i = 2,#s,2 do
      if closeToInteger(a * s[i] + b) then
        s[i] = s[i] + nudgeDistance / a
      end
    end  
  end
  local segmentCount = copyCurveToBlob(curve, buffer, nudge)
  
  local pixels = getPixelIntersections(curve, numColumns, numRows, curveToRaster)
  
  local nonContiguousSegmentCount = 0
  local function pushbackSegment(ix)
    local offset = BYTES_PER_SEGMENT * segmentCount + BYTES_PER_FULL_SEGMENT * nonContiguousSegmentCount
    for i = 0, 5 do
      local v = buffer:getF32(BYTES_PER_SEGMENT * (ix - 1) + BYTES_PER_FLOAT * i)
      buffer:setF32(offset + BYTES_PER_FLOAT * i, v)
    end
    nonContiguousSegmentCount = nonContiguousSegmentCount + 1
  end
  
  local nonContiguousPixelCount = 0
  for y, row in ipairs(pixels) do
    for x, pix in ipairs(row) do
    
      local startIndex
      if #pix == 0 then
        startIndex = 0
      elseif isContiguous(pix) then
        startIndex = FLOATS_PER_SEGMENT * (pix[1]-1)
      else
        nonContiguousPixelCount = nonContiguousPixelCount + 1
        startIndex = FLOATS_PER_FULL_SEGMENT * nonContiguousSegmentCount + 
          FLOATS_PER_SEGMENT * segmentCount + 1  -- the 1 encodes the non-contiguity
        for index, value in ipairs(pix) do
          if index == 256 then break end -- maximum of 255 curves per pixel
          pushbackSegment(value)
        end
      end
      
      local clampAsUByte = function(n) return math.max(math.min(n, 255), 0) end
      
      local nCurves = clampAsUByte(#pix)
      local windingNoAsUByte = clampAsUByte(pix.windingNo + 128)
      local combinedData = windingNoAsUByte * 256 + nCurves
      
      local maxU16 = 65535
      raster:setPixel(x-1, y-1, combinedData/maxU16, startIndex/maxU16)
    end
  end
      
  return {
    uvToRaster = uvToRaster,
    uvToCurve = uvToCurve,
    segmentCount = segmentCount,
    nonContiguousPixelCount = nonContiguousPixelCount,
    nonContiguousSegmentCount = nonContiguousSegmentCount,
    floatCount = FLOATS_PER_SEGMENT * segmentCount + FLOATS_PER_FULL_SEGMENT * nonContiguousSegmentCount
    }
end

--- class that manages a large GPU texture atlas and buffer.
-- The tiles have all have dimensions
local robin = {
  rasterWidth = 1024,  -- default dimensions, overridable in :new
  rasterHeight = 1024,
  entryWidth = 16,
  entryHeight = 16,
  pixelShaderPath = pixelShaderPath,
  vertexShaderPath = vertexShaderPath,
  shader = nil -- filled by robin.loadShader
}
robin.__index = robin

--- create a new instance
function robin.new(o)
  o = setmetatable(o or {}, robin)
  o.numEntries = 0
  o.curveBufferUsed = 0
  o.segmentCount = 0
  o.nonContiguousSegmentCount = 0
  local initialCapacity = 20000  -- should hold a small-medium font
  o.curveBuffer = lovr.graphics.newBuffer('f32', initialCapacity)
  o.rasterBuffer = lovr.graphics.newTexture(o.rasterWidth, o.rasterHeight, {
    type = '2d',
    format = 'rg16',
    linear = true,
    mipmaps = false, 
    usage = {'sample', 'transfer'},
    label = 'ROBIN raster data'
  })
  o.rasterBuffer:setSampler('nearest')
  
  return o
end

function robin:add(curve, bounds)
  local W = math.floor(self.rasterWidth / self.entryWidth)
  local x = self.numEntries % W
  local y = math.floor(self.numEntries / W)
  self.raster = self.raster or lovr.data.newImage(self.entryWidth, self.entryHeight, 'rg16')
  self.buffer = self.buffer or lovr.data.newBlob(1000000)
  
  
  local result = prepareCurve(curve, self.raster, self.buffer, bounds)
  result.dataOffset = self.curveBufferUsed / 2
  result.uvToTexture = {
    self.entryWidth / self.rasterWidth, 
    self.entryHeight / self.rasterHeight, 
    x * self.entryWidth / self.rasterWidth,
    y * self.entryHeight / self.rasterHeight
    }   

  local requiredBufferSize = BYTES_PER_FLOAT * (self.curveBufferUsed + result.floatCount)
  local currentBufferSize = self.curveBuffer:getSize()
  if currentBufferSize < requiredBufferSize then
    local newSize = math.max(currentBufferSize * 2, requiredBufferSize)
    local newBuffer = lovr.graphics.newBuffer('f32', newSize / BYTES_PER_FLOAT)
    newBuffer:setData(self.curveBuffer)
    self.curveBuffer = newBuffer
  end
  
  self.curveBuffer:setData(self.buffer, BYTES_PER_FLOAT * self.curveBufferUsed)
    
  self.rasterBuffer:setPixels(self.raster, x * self.entryWidth, y * self.entryHeight)
  
  self.numEntries = self.numEntries + 1
  
  self.curveBufferUsed = self.curveBufferUsed + result.floatCount
  
  self.nonContiguousSegmentCount = self.nonContiguousSegmentCount + result.nonContiguousSegmentCount
  self.segmentCount = self.segmentCount + result.segmentCount
  
  return result
end

function robin.necessaryDimensions(entryWidth, entryHeight, capacity)
  local rWidth, rHeight = entryWidth, entryHeight
  while rWidth / entryWidth * rHeight / entryHeight < capacity do
    if rWidth <= rHeight then 
      rWidth = rWidth * 2 
    else
      rHeight = rHeight * 2
    end
  end
  return rWidth, rHeight
end

function robin:sendBuffers(pass)
  pass:send('rasterData', self.rasterBuffer)
  pass:send('CurveData', self.curveBuffer)
end

function robin:getRasterMemoryUse()
  local bytesPerEntry = 4 * self.entryWidth * self.entryHeight
  return self.numEntries * bytesPerEntry
end

function robin:getReplicatedCurveMemoryUse()
  return 24 * self.nonContiguousSegmentCount
end

function robin:getUniqueCurveMemoryUse()
  return 16 * self.segmentCount
end

function robin:getCurveMemoryUse()
  return self:getReplicatedCurveMemoryUse() + self:getUniqueCurveMemoryUse()
end

function robin:getMemoryEfficiency()
  if self.segmentCount == 0 then
    return 1
  end
  return self:getMemoryUse() / self:getUniqueCurveMemoryUse()
end

function robin:getMemoryUse()
  return self:getRasterMemoryUse() + 4 * self.curveBufferUsed
end

function robin.loadShader()
  local pixelSource = lovr.filesystem.read(robin.pixelShaderPath)
  local vertexSource = lovr.filesystem.read(robin.vertexShaderPath)
  
  if not pixelSource then
    return "Failed to load "..pixelShaderPath
  end
  if not vertexSource then
    return "Failed to load "..vertexShaderPath
  end
  
  local success, result = pcall(lovr.graphics.newShader, vertexSource, pixelSource)
  
  if not success then
    return "Shader load failed: "..result
  end
  
  robin.shader = result
  
  return "Shader load successful"
end

return robin

