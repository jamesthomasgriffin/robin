// Raster Of Bezier Intersection Neighbourhoods (ROBIN)


/******* Uniforms, input and output data *******/

// Transforms
uniform vec4 uvToTexture;   // transform to the indexing texture 
uniform vec4 uvToCurve;     // transform to the coord. system of the Beziers

vec2 applyTransform(vec4 T, vec2 p) { return p * T.xy + T.zw; }
vec2 applyInverseTransform(vec4 T, vec2 p) { return (p - T.zw) / T.xy; }
vec4 composeTransform(vec4 T, vec4 U) { return vec4(T.xy * U.xy, T.xy * U.zw + T.zw); }
vec4 invertTransform(vec4 T) { return vec4(vec2(1.0) / T.xy, -T.zw / T.xy); }

out vec2 curveCoord;
flat out vec4 textureToCurve;

vec4 lovrmain() {
    curveCoord = applyTransform(uvToCurve, UV);
    vec4 textureToUv = invertTransform(uvToTexture);
    textureToCurve = composeTransform(uvToCurve, textureToUv);
    return DefaultPosition;
}