local robin = require 'robin'
local utf8 = require 'utf8'

local sampleChinese = [[ 人類社会のすべての構成員の固有の尊厳と平等で譲ることのできない権利とを承認することは、世界における自由、正義及び平和の基礎であるので、
人権の無視及び軽侮が、人類の良心を踏みにじった野蛮行為をもたらし、言論及び信仰の自由が受けられ、恐怖及び欠乏のない世界の到来が、一般の人々の最高の願望として宣言されたので、
人間が専制と圧迫とに対する最後の手段として反逆に訴えることがないようにするためには、法の支配によって人権を保護することが肝要であるので、
諸国間の友好関係の発展を促進することが肝要であるので、国際連合の諸国民は、国連憲章において、基本的人権、人間の尊厳及び価値並びに男女の同権についての信念を再確認し、かつ、一層大きな自由のうちで社会的進歩と生活水準の向上とを促進することを決意したので、]]
local sampleEnglish = [[Everyone has the right to freedom of thought, conscience and religion; this right includes freedom to change his religion or belief, and freedom, either alone or in community with others and in public or private, to manifest his religion or belief in teaching, practice, worship and observance.
Everyone has the right to freedom of opinion and expression; this right includes freedom to hold opinions without interference and to seek, receive and impart information and ideas through any media and regardless of frontiers.
Everyone has the right to rest and leisure, including reasonable limitation of working hours and periodic holidays with pay.]]

local function isWhitespace(cp)
  local lookup = {
      -- ASCII whitespace
      [9]   = true, -- Horizontal Tab (\t)
      [10]  = true, -- Line Feed (\n)
      [11]  = true, -- Vertical Tab (\v)
      [12]  = true, -- Form Feed (\f)
      [13]  = true, -- Carriage Return (\r)
      [32]  = true, -- Space

      -- Unicode whitespace
      [0x00A0] = true, -- No-break space
      [0x1680] = true, -- Ogham space mark
      [0x2000] = true, -- En quad
      [0x2001] = true, -- Em quad
      [0x2002] = true, -- En space
      [0x2003] = true, -- Em space
      [0x2004] = true, -- Three-per-em space
      [0x2005] = true, -- Four-per-em space
      [0x2006] = true, -- Six-per-em space
      [0x2007] = true, -- Figure space
      [0x2008] = true, -- Punctuation space
      [0x2009] = true, -- Thin space
      [0x200A] = true, -- Hair space
      [0x2028] = true, -- Line separator
      [0x2029] = true, -- Paragraph separator
      [0x202F] = true, -- Narrow no-break space
      [0x205F] = true, -- Medium mathematical space
      [0x3000] = true, -- Ideographic (CJK) space
  }
  return lookup[cp] or false
end

local function isNewline(cp)
  local lookup = {
      -- ASCII whitespace
      [10]  = true, -- Line Feed (\n)
      [11]  = true, -- Vertical Tab (\v)
      [12]  = true, -- Form Feed (\f)
      [13]  = true, -- Carriage Return (\r)

      -- Unicode
      [0x2028] = true, -- Line separator
      [0x2029] = true, -- Paragraph separator
  }
  return lookup[cp] or false
end

-- A very rough proof of concept
local RobinText = {}
RobinText.__index = RobinText

function RobinText.new(fontPath, entryWidth, entryHeight)
  if not robin.shader then
    robin.loadShader()
  end
  entryWidth = entryWidth or 16
  entryHeight = entryHeight or 16
  
  
  local o = setmetatable({}, RobinText)
  o.rasterizer = lovr.data.newRasterizer(fontPath)
  
  local rasterW, rasterH = robin.necessaryDimensions(entryWidth, entryHeight, o.rasterizer:getGlyphCount())
  
  o.robinBuffer = robin.new({
    entryWidth = entryWidth, entryHeight = entryHeight,
    rasterWidth = rasterW, rasterHeight = rasterH})
  o.characters = { count = 0 }
  
  o.sample = o.rasterizer:hasGlyphs(0x4E00) and sampleChinese or sampleEnglish

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

  if not robin.shader then return end
  
  pass:setShader(robin.shader)
  pass:setBlendMode('alpha')
  pass:setDepthTest('none')
  self.robinBuffer:sendBuffers(pass)
  
  local advance = 0
  local lineNumber = 0
  local leading = -self.rasterizer:getLeading()
  
  local lastCodepoint = nil
  for _, codepoint in utf8.codes(text) do
    self:addCharacter(codepoint)
    
    local entry = self.characters[codepoint]
    if entry then
      if not entry.skip then
        pass:send('uvToCurve', unpack(entry.uvToCurve))
        pass:send('uvToTexture', unpack(entry.uvToTexture))
        pass:send('glyphDataOffset', entry.dataOffset)
      end
      
      local x, y, X, Y = unpack(entry.bounds)
      if lastCodepoint then
        advance = advance + self.rasterizer:getKerning(lastCodepoint, codepoint)
      end      
      if isNewline(codepoint) or (wrap and advance + entry.advance > wrap) then
        advance = 0
        lineNumber = lineNumber + 1
      end
      if not isWhitespace(codepoint) then
        pass:plane(advance + (x+X)/2, lineNumber * leading + (y+Y)/2, 0, X - x, y - Y)
      end
      advance = advance + entry.advance
      
      lastCodepoint = codepoint
    end
  end
end
  


function lovr.draw(pass) 
  lovr.graphics.setBackgroundColor(0.9, 0.9, 0.9)
  pass:push()
  pass:setColor(0.1, 0.1, 0.1)
  
  local blockWidth = 16
  pass:translate(-blockWidth / 2, 1.7, -10)
  pass:scale(1/32)
  
  robinText:draw(pass, robinText.sample, blockWidth * 32)
  pass:pop()
  
  local stats = pass:getStats()
  local text = {
    "Press number keys to select font from fonts folder",
    "Use (shift) +/- to change entry dimensions",
    string.format("%.2fms", stats.gpuTime * 1000),
    string.format("Draws: %d", stats.draws),
    string.format("Entry size: %d x %d", robinText.robinBuffer.entryWidth, robinText.robinBuffer.entryHeight),
    string.format("Memory Factor: %.2f", robinText.robinBuffer:getMemoryEfficiency())
  }
  displayInfo(pass, text)
end

function displayInfo(pass, text)

  local textSize = 1.0
  local lineSpacing = 0.04
    
  local font = lovr.graphics.getDefaultFont()
  font:setPixelDensity(1)
  pass:setFont(font)
  
  pass:setShader()
  pass:setViewPose(1, mat4():identity())
  pass:setProjection('orthographic')
  pass:setDepthTest('none')
  pass:setBlendMode()
  
  local width, height = pass:getDimensions()
  
  pass:scale(textSize, -textSize, 1)
  pass:translate(1.5 * lineSpacing * width, -1.5 * lineSpacing * height, 0)
  pass:setColor(0x332211)
  for no, line in ipairs(text) do
    robinText:draw(pass, line)
    pass:translate(0, -lineSpacing * height, 0)
    --pass:text(line, 2 * lineSpacing * width, no * lineSpacing * height, -1, textSize, 0, 0, 1, 0, nil, 'left', 'top')
  end
  font:setPixelDensity()
  
end

function lovr.load()
    
  lovr.filesystem.watch()
  lovr.graphics.setTimingEnabled(true) 
    
  hudPass = lovr.graphics.newPass()
  
  fontFiles = {}
  for _, filename in ipairs(lovr.filesystem.getDirectoryItems("fonts/")) do
    if string.match(filename, "%.[tT][tT][fF]$") then
      table.insert(fontFiles, "fonts/" .. filename)
      print(fontFiles[#fontFiles])
    end
  end
  
  robinText = RobinText.new(fontFiles[1], entryWidth, entryHeight)
  robinText.file = fontFiles[1]
end

function lovr.keypressed(key, scancode, isrepeat)
  local entryWidth, entryHeight = robinText.robinBuffer.entryWidth, robinText.robinBuffer.entryHeight
  local originalW, originalH = entryWidth, entryHeight
  
  local file = robinText.file
  local shift = lovr.system.isKeyDown("lshift", "rshift")
  
  if key == "=" then
    if shift then
      entryHeight = math.min(entryHeight * 2, 64)
    else
      entryWidth = math.min(entryWidth * 2, 64)
    end
  elseif key == "-" then
    if shift then
      entryHeight = math.max(entryHeight / 2, 1)
    else
      entryWidth = math.max(entryWidth / 2, 1)
    end
  end

  key = tonumber(key)
  if key and not isrepeat then
    file = fontFiles[key] -- nil is valid, it's the default font
  end
  
  if originalW ~= entryWidth or originalH ~= entryHeight 
    or robinText.file ~= file then
    robinText = RobinText.new(file, entryWidth, entryHeight)
    robinText.file = file
  end
end

function lovr.filechanged(path, action, oldpath)
  if action == "modify" and (path == robin.pixelShaderPath or path == robin.vertexShaderPath) then
    print(robin.loadShader())
  end
end

