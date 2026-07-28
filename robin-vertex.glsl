// Raster Of Bézier Intersection Neighbourhoods (ROBIN)


/******* Uniforms, input and output data *******/

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

vec4 composeTransform(vec4 T, vec4 U) { return vec4(T.xy * U.xy, T.xy * U.zw + T.zw); }
vec4 invertTransform(vec4 T) { return vec4(vec2(1.0) / T.xy, -T.zw / T.xy); }

vec4 lovrmain() {
    glyph = glyphData[glyphIndex];
    vec4 textureToUv = invertTransform(glyph.uvToTexture);    
    glyph.textureToCurve = composeTransform(glyph.uvToCurve, textureToUv);
    
    return DefaultPosition;
}