// Raster Of Bézier Intersection Neighbourhoods (ROBIN)


/******* Uniforms, input and output data *******/

struct RobinPerGlyph {
    vec4 uvToCurve;
    vec4 uvToTexture;
    vec4 textureToCurve;
    int dataOffset;
};
flat out RobinPerGlyph glyph;

// Uniforms
uniform vec4 uvToTexture;   // transform to the indexing texture 
uniform vec4 uvToCurve;     // transform to the coord. system of the Béziers
uniform int glyphDataOffset;

//vec2 applyTransform(vec4 T, vec2 p) { return p * T.xy + T.zw; }
//vec2 applyInverseTransform(vec4 T, vec2 p) { return (p - T.zw) / T.xy; }
vec4 composeTransform(vec4 T, vec4 U) { return vec4(T.xy * U.xy, T.xy * U.zw + T.zw); }
vec4 invertTransform(vec4 T) { return vec4(vec2(1.0) / T.xy, -T.zw / T.xy); }

vec4 lovrmain() {
    vec4 textureToUv = invertTransform(uvToTexture);
    
    glyph.uvToCurve = uvToCurve;
    glyph.uvToTexture = uvToTexture;
    glyph.textureToCurve = composeTransform(uvToCurve, textureToUv);
    glyph.dataOffset = glyphDataOffset;
    
    return DefaultPosition;
}