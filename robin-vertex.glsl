// Raster Of Bézier Intersection Neighbourhoods (ROBIN)

struct RobinGlyph {
    vec4 uvToCurve;
    vec4 uvToTexture;
    vec4 textureToCurve;
    int dataOffset;
};
flat out RobinGlyph glyph;

readonly buffer GlyphData {
    RobinGlyph[] glyphData;
};

uniform int glyphIndex;

vec4 lovrmain() {
    glyph = glyphData[glyphIndex];    
    return DefaultPosition;
}