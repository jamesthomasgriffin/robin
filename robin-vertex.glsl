// Raster Of Bézier Intersection Neighbourhoods (ROBIN)

uniform int instanceOffset;

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

struct GlyphInstance {
    vec2 position;
    int glyphIndex;
}; 

readonly buffer GlyphInstances {
    GlyphInstance[] glyphInstances;
};

vec2 applyTransform(vec4 T, vec2 p) { return p * T.xy + T.zw; }

vec4 lovrmain() {
    GlyphInstance instance = glyphInstances[InstanceIndex + instanceOffset];
    glyph = glyphData[instance.glyphIndex];
    vec2 q = applyTransform(glyph.uvToCurve, VertexPosition.xy) + instance.position;
    return Projection * View * Transform * vec4(q, 0, 1);
}