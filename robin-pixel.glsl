// Raster Of Bezier Intersection Neighbourhoods (ROBIN)


/******* Uniforms and input data *******/

in vec2 curveCoord;
flat in vec4 textureToCurve;

// Transforms
uniform vec4 uvToTexture;   // transform to the indexing texture 
uniform vec4 uvToCurve;     // transform to the coord. system of the Beziers

vec2 applyTransform(vec4 T, vec2 p) { return p * T.xy + T.zw; }
vec2 applyInverseTransform(vec4 T, vec2 p) { return (p - T.zw) / T.xy; }
vec4 composeTransform(vec4 T, vec4 U) { return vec4(T.xy * U.xy, T.xy * U.zw + T.zw); }
vec4 invertTransform(vec4 T) { return vec4(vec2(1.0) / T.xy, -T.zw / T.xy); }

// The Beziers are triples of vec2's within this buffer
readonly buffer CurveData {
    vec2[] curveData;
};

// Start of data in CurveData
uniform int glyphDataOffset;

// Each texel contains a partial computation of the winding number,
// the number of Beziers and the index of the initial Bezier, see the
// code for the encoding.  One bit encodes whether the Beziers are contiguous
// or not (which determines the stride).
uniform sampler2D rasterData;

/******* Bernstein quadratic solving *******/

uint rootEligibility(float y1, float y2, float y3, float y)
{
    uint shift = uint(y > y1) | uint(y > y2) << 1 | uint(y > y3) << 2;

    // This lookup table is taken from the slug algorithm
	// Eligibility is returned in bits 0 and 8.
	return ((0x2E74U >> shift) & 0x0101U);
}

vec2 evaluateQuadratic(float a, float b, float c, vec2 t)
{
    return (a * t + b) * t + c;
}

struct QuadraticRoots {
    vec2 roots;
    bool doubleRoot;
};

QuadraticRoots solveQuadratic(float a, float b, float c)
{
    QuadraticRoots res;   
    
	// If nearly linear, then solve bt + c = 0.
	if (abs(a) < 1.0 / 65536.0) {
        res.roots = vec2(-c / b);
        res.doubleRoot = false;
    } else {
        float d = sqrt(max(b * b - 4 * a * c, 0.0));
        res.roots = vec2(-b - d, -b + d) / (2 * a);
        res.doubleRoot = d == 0;        
    }    
    return res;
}


/******* Crossing number of a quadratic Bezier *******/

// This can be moved into the calling function, but care is needed, the a==b
// case is very important to get correct.
float my_step(float a, float b) {
    return 1 - step(a, b);
}

// The "proximity" (might need a better name) is used in anti-aliasing
float closestProximity(float a, float b) {
    return abs(a) < abs(b) ? a : b;
}

// Computes the number of times (with parity) a piecewise linear path
//   (-inf, lineY) --> (q.x, lineY) --> (q.x, q.y)
// crosses the quadratic Bezier curve defined by control points p1, p2, p3
// returns a vec3 containing the total, and two "proximity" values representing
// the distance from q to the Bezier in the x and y directions along with the 
// sign of the crossing number change at the closest points.
vec3 crossingNumberOfBezier(vec2 p1, vec2 p2, vec2 p3, float lineY, vec2 q)
{
    float change = 0.0;
    float proximityX = 3.4e+38;
    float proximityY = 3.4e+38;
        
    const vec2 a = p1 - p2 * 2.0 + p3;
    const vec2 b = 2 * (p2 - p1);
    const vec2 c = p1;
    
    // 1(q.x > p1.x) * (1(p3.y > lineY) - 1(p1.y > lineY)) + 
    // 1(p3.y > lineY) * (1(p3.x > q.x) - 1(p1.x > q.x))
    change += my_step(q.x, p1.x) * (my_step(lineY, p3.y) - my_step(lineY, p1.y));
    change += my_step(lineY, p3.y) * (my_step(q.x, p3.x) - my_step(q.x, p1.x));
    
    const uint vCode = rootEligibility(p1.x, p2.x, p3.x, q.x);
    if (vCode != 0U)
	{
        const QuadraticRoots res = solveQuadratic(a.x, b.x, c.x - q.x);
        const vec2 y = evaluateQuadratic(a.y, b.y, c.y, res.roots);
        
		if ((vCode & 1U) != 0U)
		{
			change -= my_step(q.y, y.r);
            if (!res.doubleRoot) proximityY = closestProximity(proximityY, -(q.y - y.r));
		}

		if (vCode > 1U)
		{
			change += my_step(q.y, y.g);
            if (!res.doubleRoot) proximityY = closestProximity(proximityY, q.y - y.g);
		}
    }    
    
    const uint hCode = rootEligibility(p1.y, p2.y, p3.y, q.y);
    if (hCode != 0U)
	{
        const QuadraticRoots res = solveQuadratic(a.y, b.y, c.y - q.y);
                
        if(!res.doubleRoot) {
            const vec2 x = evaluateQuadratic(a.x, b.x, c.x, res.roots);
            if ((hCode & 1U) != 0U)
            {
                proximityX = closestProximity(proximityX, -(q.x - x.r));
            }

            if (hCode > 1U)
            {
                proximityX = closestProximity(proximityX, q.x - x.g);
            }
        }
    }    
    return vec3(change, proximityX, proximityY);
}

vec4 debugColour = vec4(0);

float robinRender(vec2 uv)
{
    vec2 texCoord = applyTransform(uvToTexture, clamp(uv, vec2(0,0), vec2(0.999, 0.999)));    

    ivec2 gridCoord = ivec2(textureSize(rasterData, 0) * texCoord);
    uvec2 gridData = uvec2(round(texelFetch(rasterData, gridCoord, 0).rg * 65535.0));
    
    vec2 anchorPosition = applyTransform(textureToCurve, 
            vec2(gridCoord) / textureSize(rasterData, 0));
            
    int partialWindingNumber = int(gridData.r >> 8) - 128;
    
    int numSegments = int(gridData.r & 255);
    
    int startingIndex = glyphDataOffset + int(gridData.g >> 1);
    int indexStride = ((gridData.g & 1u) == 1u) ? 3 : 2;
    
    // The sign convention is switched between the pixel shader and the CPU code
    // TODO, change this shader
	float windingNumber = -partialWindingNumber;
        
    float proximityX = 1.0e30;
    float proximityY = 1.0e30;
	for (int i = 0; i < numSegments; i++)
	{
		int curveIndex = startingIndex + indexStride * i;
        
		vec2 p1 = curveData[curveIndex + 0];
		vec2 p2 = curveData[curveIndex + 1];
		vec2 p3 = curveData[curveIndex + 2];
        
        vec3 cnb = crossingNumberOfBezier(p1, p2, p3, anchorPosition.y, curveCoord);
        
        windingNumber += cnb.x;
        proximityX = closestProximity(proximityX, cnb.y);
        proximityY = closestProximity(proximityY, cnb.z);
	}
    
    // Turns the winding number of "proximities" into an anti-aliased value
	vec2 emsPerPixel = fwidth(curveCoord);
	vec2 pixelsPerEm = 1.2 / emsPerPixel;
    float proximity = closestProximity(proximityX * pixelsPerEm.x, -proximityY * pixelsPerEm.y);
    if (windingNumber==0) 
        return max(0.5 - 0.5 * abs(proximity), 0.0);
    else if (windingNumber == 1)
        return (proximity > 0) ? 1.0 : min(0.5 - proximity, 1.0);
    else if (windingNumber == -1)
        return (proximity < 0) ? 1.0 : min(0.5 + proximity, 1.0);
    return 1.0; 
}

vec4 lovrmain()
{
	vec4 res = vec4(Color.rgb, robinRender(UV) * Color.a); 
    return mix(res, debugColour, debugColour.a);
}