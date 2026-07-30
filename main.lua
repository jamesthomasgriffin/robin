local robin = require 'robin'
local utf8 = require 'utf8'

local sampleChinese = [[人類社会のすべての構成員の固有の尊厳と平等で譲ることのできない権利とを承認することは、世界における自由、正義及び平和の基礎であるので、
人権の無視及び軽侮が、人類の良心を踏みにじった野蛮行為をもたらし、言論及び信仰の自由が受けられ、恐怖及び欠乏のない世界の到来が、一般の人々の最高の願望として宣言されたので、
人間が専制と圧迫とに対する最後の手段として反逆に訴えることがないようにするためには、法の支配によって人権を保護することが肝要であるので、
諸国間の友好関係の発展を促進することが肝要であるので、国際連合の諸国民は、国連憲章において、基本的人権、人間の尊厳及び価値並びに男女の同権についての信念を再確認し、かつ、一層大きな自由のうちで社会的進歩と生活水準の向上とを促進することを決意したので、]]
local sampleEnglish = [[Everyone has the right to freedom of thought, conscience and religion; this right includes freedom to change his religion or belief, and freedom, either alone or in community with others and in public or private, to manifest his religion or belief in teaching, practice, worship and observance.
Everyone has the right to freedom of opinion and expression; this right includes freedom to hold opinions without interference and to seek, receive and impart information and ideas through any media and regardless of frontiers.
Everyone has the right to rest and leisure, including reasonable limitation of working hours and periodic holidays with pay.]]

-- A rough proof of concept
local RobinText = {}
RobinText.__index = RobinText

function RobinText.new(font, entryWidth, entryHeight)
  if not robin.shader then
    print(robin.loadShader())
  end
  entryWidth = entryWidth or 16
  entryHeight = entryHeight or 16
  
  
  local o = setmetatable({}, RobinText)
  o.font = font or lovr.graphics.getDefaultFont()
  
  o.rasterizer = o.font:getRasterizer()
  
  local rasterW, rasterH = robin.necessaryDimensions(entryWidth, entryHeight, o.rasterizer:getGlyphCount())
  
  o.robinBuffer = robin.new({
    entryWidth = entryWidth, entryHeight = entryHeight,
    rasterWidth = rasterW, rasterHeight = rasterH})
  o.characters = { count = 0 }
  
  o.sample = o.rasterizer:hasGlyphs(0x4E00) and sampleChinese or sampleEnglish

  o.instanceBuffer = robin.InstanceBuffer.new()
  o.mesh = lovr.graphics.newMesh({
    { 'VertexPosition', 'vec3' },
    { 'VertexUV', 'vec2' }
  }, {
    { 0, 1, 0, 0, 1 },
    { 1, 1, 0, 1, 1 },
    { 0, 0, 0, 0, 0 },
    { 0, 0, 0, 0, 0 },
    { 1, 1, 0, 1, 1 },
    { 1, 0, 0, 1, 0 }
  })
  return o
end

function RobinText:addCharacter(codepoint)
  if self.characters[codepoint] then return end
  
  local glyph = self.rasterizer:getCurves(codepoint)
  if not glyph then return end
  
  self.characters.count = self.characters.count + 1
  
  local hm, vm, hM, vM = self.rasterizer:getBoundingBox(codepoint)
  
  local entry = #glyph > 0 and self.robinBuffer:add(glyph, {hm, hM, vm, vM}) or { skip = true }
  
  entry.bounds = {hm, vm, hM, vM}
  entry.advance = self.rasterizer:getAdvance(codepoint)
  
  self.characters[codepoint] = entry  
end

function RobinText:draw(pass, text, wrap)
  pass:push()
  pass:scale(1.0 / self.font:getPixelDensity())
  local instanceOffset = self.instanceBuffer.size    
  
  local lineHeight = -self.rasterizer:getLeading() * self.font:getLineSpacing()
  local lineOffset = -self.rasterizer:getAscent()
  local instanceCount = 0
  
  local lines = self.font:getLines(text, wrap or 1e16)
  for lineIndex, line in ipairs(lines) do
    local lastCodepoint = nil
    local advance = 0
    for _, codepoint in utf8.codes(line) do
      self:addCharacter(codepoint)
      
      local entry = self.characters[codepoint]
      if entry then
      
        if lastCodepoint then
          advance = advance + self.rasterizer:getKerning(lastCodepoint, codepoint)
        end
        
        if not entry.skip then
          instanceCount = instanceCount + 1
          self.instanceBuffer:pushback(advance, (lineIndex-1) * lineHeight + lineOffset, entry.index)
        end
        
        advance = advance + entry.advance      
        lastCodepoint = codepoint
      end
    end
  end
  
  pass:setShader(robin.shader)
  self.robinBuffer:sendBuffers(pass)
  pass:send("instanceOffset", instanceOffset)
  pass:send("GlyphInstances", self.instanceBuffer.buffer)
  pass:draw(self.mesh, nil, instanceCount)
  pass:pop()
end

local modes = {none = "None", both = "Both MSDF and ROBIN", msdf = "MSDF (64x64)", robin = "ROBIN" }
modes.keys = { u = modes.none, r = modes.robin, t = modes.msdf, y = modes.both }
modes.selected = modes.robin
  
function lovr.draw(pass)
  lovr.graphics.setBackgroundColor(1, 1, 1)
  local mode = modes.selected
    
  if not (mode == modes.none) then
    robinText.instanceBuffer:clear()
    
    local text = robinText.sample
    pass:setFont(robinText.font)
    
    pass:push()
    pass:setBlendMode('alpha')
    pass:setDepthTest('none')
    
    local blockWidth = 12
    pass:translate(-blockWidth / 2, 1.7, -10)
    
    
    local robin, msdf, both = mode == modes.robin, mode == modes.msdf, mode == modes.both
    
    robinText.font:setLineSpacing(1.0)
    if msdf or both then
      if both then
        pass:setColor(0.5, 0.1, 0.1)
        robinText.font:setLineSpacing(2.0)
      else      
        pass:setColor(0, 0, 0)
      end
      pass:text(text, 0, 0, 0, 1.0, 0, 0, 0, 1, blockWidth, "left", "top")
    end
    
    if robin or both then
      if both then -- interleave
        pass:translate(0, robinText.font:getHeight(), 0)
      end
      pass:setColor(0, 0, 0)
      robinText:draw(pass, text, blockWidth)
    end
    pass:pop()
  end
  
  local stats = pass:getStats()
  local text = {
    "Mode: "..mode.." (R, T, Y, U) to change, F for fullscreen",
    string.format("Press 1 to %d to select font from folder (or 0 is default) ", #loadedFonts),
    "Use (shift) +/- to change entry dimensions",
    string.format("%.2fms", stats.gpuTime * 1000),
    string.format("Draws: %d", stats.draws),
    string.format("Entry size: %d x %d", robinText.robinBuffer.entryWidth, robinText.robinBuffer.entryHeight),
    string.format("Memory Factor: %.2f", robinText.robinBuffer:getMemoryEfficiency())
  }
  displayInfo(pass, table.concat(text, '\n'))
end

function displayInfo(pass, text)

  local textSize = 0.4
  pass:push()
  
  pass:setBlendMode('alpha')
  pass:setDepthTest('none')
  pass:setShader()
  pass:setViewPose(1, mat4():identity())
  pass:setProjection('orthographic')
  pass:scale(1, -1)
  
  local width, height = pass:getDimensions()
  
  pass:scale(textSize)
  robinText.font:setLineSpacing(0.8)
  pass:translate(0.05 * width, -0.04 * height, 0)
  pass:setColor(0x332211)
  local savedPD = robinText.font:getPixelDensity()
  robinText.font:setPixelDensity(1)
  
  if modes.selected == modes.msdf then
    pass:scale(1, -1)
    pass:text(text, 0, 0, 0, 1, 0, 0, 0, 1, 1e16, "left", "top")
  else
    robinText:draw(pass, text)
  end
  
  pass:pop()
  robinText.font:setPixelDensity(savedPD)
end

local function setActiveFont(k, entryWidth, entryHeight)
  local font = loadedFonts[k] or loadedFonts.default
  robinText = RobinText.new(font, entryWidth, entryHeight)
  robinText.fontIndex = font and k or 0
end

function lovr.load()
    
  lovr.filesystem.watch()
  lovr.graphics.setTimingEnabled(true) 
    
  hudPass = lovr.graphics.newPass()
  
  loadedFonts = {}
  loadedFonts.default = lovr.graphics.getDefaultFont() 
  for _, filename in ipairs(lovr.filesystem.getDirectoryItems("fonts/")) do
    if string.match(filename, "%.[tT][tT][fF]$") then
      local path = "fonts/" .. filename
      local font = lovr.graphics.newFont(path, 64)
      if font then
        table.insert(loadedFonts, font)
        print("Loaded ", path)
      else
        print("Failed to load ", path)
      end
    end
  end
  
  setActiveFont(1)
end

function lovr.keypressed(key, scancode, isrepeat)
  print("Keypress", key)
  
  local entryWidth, entryHeight = robinText.robinBuffer.entryWidth, robinText.robinBuffer.entryHeight
  
  local originalFontIndex = robinText.fontIndex
  local originalW, originalH = entryWidth, entryHeight
  
  local shiftDown = lovr.system.isKeyDown("lshift", "rshift")
  
  if key == "=" then
    if shiftDown then
      entryHeight = math.min(entryHeight * 2, 64)
    else
      entryWidth = math.min(entryWidth * 2, 64)
    end
  elseif key == "-" then
    if shiftDown then
      entryHeight = math.max(entryHeight / 2, 1)
    else
      entryWidth = math.max(entryWidth / 2, 1)
    end
  end
  
  local newMode = modes.keys[key]
  modes.selected = newMode or modes.selected  

  local fontIndex = tonumber(key) or originalFontIndex
  
  if originalW ~= entryWidth or originalH ~= entryHeight 
    or originalFontIndex ~= fontIndex then
      setActiveFont(fontIndex, entryWidth, entryHeight)
  end
  
  if key == 'f' then
    lovr.system.setWindowFullscreen(not lovr.system.isWindowFullscreen())
  elseif key == 'escape' then
    lovr.event.quit()
  end
end

function lovr.filechanged(path, action, oldpath)
  if action == "modify" and (path == robin.pixelShaderPath or path == robin.vertexShaderPath) then
    print(robin.loadShader())
  end
end

