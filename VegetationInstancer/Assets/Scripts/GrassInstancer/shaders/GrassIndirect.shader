Shader"Unlit/GrassBladeIndirect"
{
    Properties
    {
        _MainTex ("Main Tex", 2D) = "white" {}
        _PrimaryCol ("Primary Color", Color) = (1, 1, 1)
        _SecondaryCol ("Secondary Color", Color) = (1, 0, 1)
        _AOColor ("AO Color", Color) = (1, 0, 1)
        _TipColor ("Tip Color", Color) = (0, 0, 1)
        _Scale ("Scale", Range(0.0, 2.0)) = 0.0
        _MeshDeformationLimitLow ("Mesh Deformation low limit", Range(0.0, 5.0)) = 0.08
        _MeshDeformationLimitTop ("Mesh Deformation top limit", Range(0.0, 5.0)) = 2.0
        _WindNoiseScale ("Wind Noise Scale", float) = 0.0
        _WindStrength ("Wind Strength", float) = 1.0
        _WindSpeed ("Wind Speed", Vector) = (0, 0, 0, 0)
        _WindCutoff("Wind Cutoff", float) = 300.0
    }
    SubShader
    {
        Tags { "RenderType"="Opaque" }
        LOD 100
        Cull Off

        Pass
        {
            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            // make fog work
            #pragma multi_compile_fog
            #pragma multi_compile_instancing
			#pragma target 4.5

            #include "UnityCG.cginc"

            struct appdata
            {
                float4 vertex : POSITION;
                float2 uv : TEXCOORD0;
            };

            struct v2f
            {
                float2 uv : TEXCOORD0;
                UNITY_FOG_COORDS(1)
                float4 vertex : SV_POSITION;
            };

            //generated by shadergraph
            inline float Unity_SimpleNoise_RandomValue_float (float2 uv) {
                  return frac(sin(dot(uv, float2(12.9898, 78.233)))*43758.5453);
            }
            //generated by shadergraph
            inline float Unity_SimpleNnoise_Interpolate_float (float a, float b, float t) {
                 return (1.0-t)*a + (t*b);
            }
            //generated by shadergraph
            inline float Unity_SimpleNoise_ValueNoise_float (float2 uv) {
                float2 i = floor(uv);
                float2 f = frac(uv);
                f = f * f * (3.0 - 2.0 * f);

                uv = abs(frac(uv) - 0.5);
                float2 c0 = i + float2(0.0, 0.0);
                float2 c1 = i + float2(1.0, 0.0);
                float2 c2 = i + float2(0.0, 1.0);
                float2 c3 = i + float2(1.0, 1.0);
                float r0 = Unity_SimpleNoise_RandomValue_float(c0);
                float r1 = Unity_SimpleNoise_RandomValue_float(c1);
                float r2 = Unity_SimpleNoise_RandomValue_float(c2);
                float r3 = Unity_SimpleNoise_RandomValue_float(c3);

                float bottomOfGrid = Unity_SimpleNnoise_Interpolate_float(r0, r1, f.x);
                float topOfGrid = Unity_SimpleNnoise_Interpolate_float(r2, r3, f.x);
                float t = Unity_SimpleNnoise_Interpolate_float(bottomOfGrid, topOfGrid, f.y);
                return t;
            }
            //generated by shadergraph
            void Unity_SimpleNoise_float(float2 UV, float Scale, out float Out) {
                float t = 0.0;

                float freq = pow(2.0, float(0));
                float amp = pow(0.5, float(3-0));
                t += Unity_SimpleNoise_ValueNoise_float(float2(UV.x*Scale/freq, UV.y*Scale/freq))*amp;

                freq = pow(2.0, float(1));
                amp = pow(0.5, float(3-1));
                t += Unity_SimpleNoise_ValueNoise_float(float2(UV.x*Scale/freq, UV.y*Scale/freq))*amp;

                freq = pow(2.0, float(2));
                amp = pow(0.5, float(3-2));
                t += Unity_SimpleNoise_ValueNoise_float(float2(UV.x*Scale/freq, UV.y*Scale/freq))*amp;

                Out = t;
            }
            
            // terrain height related variables and functions -------------------------
            uniform StructuredBuffer<float> heightMap;
            uniform int resolution;
            uniform float4 sampleSize;
            uniform float4 AABBMin;
            uniform float4 AABBMax;
            
            struct Triangle
            {
                float3 V0;
                float3 V1;
                float3 V2;
                float3 Normal;
            };

            Triangle MakeTriangle(float3 v0, float3 v1, float3 v2)
            {
                Triangle tri;
                tri.V0 = v0;
                tri.V1 = v1;
                tri.V2 = v2;
                tri.Normal = normalize(cross(v1 - v0, v2 - v0));
                return tri;
            }

            float TriSampleHeight(Triangle tri, float2 position)
            {
                    // plane formula: a(x - x0) + b(y - y0) + c(z - z0) = 0
                    // <a,b,c> is a normal vector for the plane
                    // (x,y,z) and (x0,y0,z0) are any points on the plane
                return (-tri.Normal.x * (position.x - tri.V0.x) - tri.Normal.z * (position.y - tri.V0.z)) / tri.Normal.y + tri.V0.y;
            }

            bool IsWithinBounds(float2 worldPos)
            {
                return
                        worldPos.x >= AABBMin.x &&
                        worldPos.y >= AABBMin.z &&
                        worldPos.x <= AABBMax.x &&
                        worldPos.y <= AABBMax.z;
            }

            float3 GetWorldVertex(int2 heightMapCrds)
            {
                int i = heightMapCrds.x + heightMapCrds.y * resolution;
                float3 vertexPercentages = float3
                (
                    (float) heightMapCrds.x / (resolution - 1),
                    heightMap[heightMapCrds.x * resolution + heightMapCrds.y],
                    (float) heightMapCrds.y / (resolution - 1)
                );
                return AABBMin.xyz + (AABBMax.xyz - AABBMin.xyz) * vertexPercentages;
            }

            Triangle GetTriAtPosition(float2 worldPosition)
            {
                float2 localPos =
                float2(
                        worldPosition.x - AABBMin.x,
                        worldPosition.y - AABBMin.z);
                float2 samplePos = localPos / sampleSize.xy;
                int2 sampleFloor = int2(floor(samplePos.x), floor(samplePos.y));
                float2 sampleDecimal = samplePos - sampleFloor;
                bool upperLeftTri = sampleDecimal.y > sampleDecimal.x;
                int2 v1Offset = upperLeftTri ? int2(0, 1) : int2(1, 1);
                int2 v2Offset = upperLeftTri ? int2(1, 1) : int2(1, 0);
                float3 v0 = GetWorldVertex(sampleFloor);
                float3 v1 = GetWorldVertex(sampleFloor + v1Offset);
                float3 v2 = GetWorldVertex(sampleFloor + v2Offset);
                return MakeTriangle(v0, v1, v2);
            }

            float4 SampleHeight(float2 worldPosition)
            {
                if (!IsWithinBounds(worldPosition)) // return crazy value instead of throwing an error
                    return float4(-10000, 0, 0, 0);

                Triangle tri = GetTriAtPosition(worldPosition);
                return float4(TriSampleHeight(tri, worldPosition), tri.Normal.x, tri.Normal.y, tri.Normal.z);
            }
            // ------------------------------------------------------------------------
            
            // texture related variables and functions --------------------------------
            uniform StructuredBuffer<float> textureMapAllTextures;
            uniform int terrainPosX;
            uniform int terrainPosY;
            uniform float terrainSizeX;
            uniform float terrainSizeY;
            uniform int textureArraySizeX;
            uniform int textureArraySizeY;
            uniform int resolutionTex;
            uniform int textureCount;

            int round(float val)
            {
                if (val % 1 > 0.5)
                    return (int) (val + 1);
                return (int) (val);
            }

            float GetTextureAtPos(float2 worldPos, int texIndex)
            {
                if (texIndex >= textureCount || texIndex < 0)
                    return 0;

                // terrains cannot be rotated, so we don't have to worry about rotation
                float2 relativePosition = worldPos - float2(terrainPosX, terrainPosY);
                int2 pos = int2
                (
                    (int) round((relativePosition.x / terrainSizeX) * textureArraySizeX),
                    (int) round((relativePosition.y / terrainSizeY) * textureArraySizeY)
                );

                if (pos.x > textureArraySizeX)
                    pos.x = textureArraySizeX - 1;
                if (pos.y > textureArraySizeY)
                    pos.y = textureArraySizeY - 1;

                return textureMapAllTextures[pos.x + resolutionTex * (pos.y + textureCount * texIndex)];
            }
            // ---------------------------------------------------------------------

            // generation related variables and function ------------------------------
            int chunkPosX;
            int chunkPosZ;
            uniform float randomSeed;
            uniform float D1Size;
            uniform float chunkSize;
            uniform float plantDistance;
            uniform float maxSlope;
            uniform float sizeChange;
            uniform int rotate;
            uniform float displacement;
            uniform int textureIndex;
            uniform float falloff;
            
            // generates random value between min and max
            float GenerateRandom(float index, float min, float max)
            {
                float seed = randomSeed * index * 0.193728912263;
                float fracVal = frac(sin(seed) * 43758.5453);
                float minMaxDist = max - min;
                return min + fracVal * minMaxDist;
            }
            
            // which trs is the right one ?
            float4x4 trs(float3 t, float4 r, float3 s)
            {
                float4x4 res;
                res._11 = (1.0-2.0*(r.y*r.y+r.z*r.z))*s.x;
                res._21 = (r.x*r.y+r.z*r.w)*s.x*2.0;
                res._31 = (r.x*r.z-r.y*r.w)*s.x*2.0;
                res._41 = 0.0;
                res._12 = (r.x*r.y-r.z*r.w)*s.y*2.0;
                res._22 = (1.0-2.0*(r.x*r.x+r.z*r.z))*s.y;
                res._32 = (r.y*r.z+r.x*r.w)*s.y*2.0;
                res._42 = 0.0;
                res._13 = (r.x*r.z+r.y*r.w)*s.z*2.0;
                res._23 = (r.y*r.z-r.x*r.w)*s.z*2.0;
                res._33 = (1.0-2.0*(r.x*r.x+r.y*r.y))*s.z;
                res._43 = 0.0;
                res._14 = t.x;
                res._24 = t.y;
                res._34 = t.z;
                res._44 = 1.0;
                return res;
            }

            float4 EulerToQuaternion(float3 euler)
            {
                float3 halfAngles = euler * 0.5;
                float3 c = cos(halfAngles);
                float3 s = sin(halfAngles);

                float4 qx = float4(s.x, 0, 0, c.x);
                float4 qy = float4(0, s.y, 0, c.y);
                float4 qz = float4(0, 0, s.z, c.z);

                float4 qxy = float4
                (
                    qx.w * qy.x + qx.x * qy.w + qx.y * qy.z - qx.z * qy.y,
                    qx.w * qy.y - qx.x * qy.z + qx.y * qy.w + qx.z * qy.x,
                    qx.w * qy.z + qx.x * qy.y - qx.y * qy.x + qx.z * qy.w,
                    qx.w * qy.w - qx.x * qy.x - qx.y * qy.y - qx.z * qy.z
                );

                return float4
                (
                    qxy.w * qz.x + qxy.x * qz.w + qxy.y * qz.z - qxy.z * qz.y,
                    qxy.w * qz.y - qxy.x * qz.z + qxy.y * qz.w + qxy.z * qz.x,
                    qxy.w * qz.z + qxy.x * qz.y - qxy.y * qz.x + qxy.z * qz.w,
                    qxy.w * qz.w - qxy.x * qz.x - qxy.y * qz.y - qxy.z * qz.z
                );
            }

            float4x4 GeneratePosRotScale(int index)
            {
                float xDisplacement = GenerateRandom(index * 0.904735, -displacement, displacement);
                float zDisplacement = GenerateRandom(index * 0.290374, -displacement, displacement);
    
                float x = xDisplacement + chunkPosX - chunkSize / 2 + (index / D1Size) * chunkSize / plantDistance;
                float z = zDisplacement + chunkPosZ - chunkSize / 2 + (index % D1Size) * chunkSize / plantDistance;
                float4 yAndNormal = SampleHeight(float2(x, z));
                float y = yAndNormal.x;
                float3 normal = yAndNormal.yzw;
    
                // get max allowed texture value
                float texValueAtPos = GetTextureAtPos(float2(x, z), textureIndex);

                // check slope and texture
                if (texValueAtPos < falloff || normal.y < maxSlope)
                    return trs(float3(0, -10000, 0), float4(0, 0, 0, 1), float3(1, 1, 1));
    
                float3 pos = float3(x, y, z);
    
                float4 q = float4(0, 0, 0, 1);
                if (rotate == 1)
                    q = EulerToQuaternion(float3(0, GenerateRandom(index * 0.0983633, 0, 360), 0));
    
                float newSize = GenerateRandom(index * 0.45729204, 1 / sizeChange, sizeChange);
                if (texValueAtPos >= falloff)
                    newSize *= max(texValueAtPos, 0.1);
    
                return trs(pos, q, newSize);
            }
            // ------------------------------------------------------------------------
            
            // material variables and functions ------------------------------------
            uniform float4 LightDir;
            uniform float4 CamPos;
            uniform float ViewRangeSq;

            sampler2D _MainTex;
            float4 _MainTex_ST;
            float4 _PrimaryCol, _SecondaryCol, _AOColor, _TipColor;
            float _Scale;
            float _MeshDeformationLimitLow;
            float _MeshDeformationLimitTop;
            float4 _WindSpeed;
            float _WindStrength;
            float _WindNoiseScale;
            float _WindCutoff;

            float4 RotateAroundXInDegrees(float4 vertex, float degrees)
            {
                float alpha = degrees * UNITY_PI / 180.0;
                float sina, cosa;
                sincos(alpha, sina, cosa);
                float2x2 m = float2x2(cosa, -sina, sina, cosa);
                return float4(mul(m, vertex.yz), vertex.xw).zxyw;
            }

            v2f vert (appdata v, uint instanceID : SV_InstanceID)
            {
                v2f o;
                
                float4x4 PosRotSizeMatrix = GeneratePosRotScale(instanceID);
                float3 positionWorldSpace = mul(PosRotSizeMatrix, float4(v.vertex.xyz, 1));
    
                float distToCam = (CamPos.x - positionWorldSpace.x) * (CamPos.x - positionWorldSpace.x) +
                                  (CamPos.y - positionWorldSpace.y) * (CamPos.y - positionWorldSpace.y) +
                                  (CamPos.z - positionWorldSpace.z) * (CamPos.z - positionWorldSpace.z);
    
                if (distToCam > ViewRangeSq || GenerateRandom(instanceID, 0, ViewRangeSq) < distToCam) // second part gradually removes grass with distance
                {
                    o.uv = TRANSFORM_TEX(v.uv, _MainTex);
                    o.vertex = mul(UNITY_MATRIX_VP, float4(positionWorldSpace.x, positionWorldSpace.y - 1, positionWorldSpace.z, 1));
                    return o;
                }
                float sqrWindCutoff = _WindCutoff * _WindCutoff;
    
                //applying transformation matrix
                float4 localPosition = RotateAroundXInDegrees(v.vertex, 90.0f);
                positionWorldSpace += localPosition.xyz;
                positionWorldSpace.y += 0.5f;

                //move world UVs by time
                float4 worldPos = float4(positionWorldSpace, 1);
                o.uv = TRANSFORM_TEX(v.uv, _MainTex);
                if (distToCam < sqrWindCutoff || instanceID%4 == 0) // if distance is higher than max wind dist, only animate 1/4 grass objects
                {
                    //creating noise from world UVs
                    float2 worldUV = worldPos.xz + _WindSpeed * _Time.y;
                    float noise = 0;
                    Unity_SimpleNoise_float(worldUV, _WindNoiseScale, noise);
                    noise -= .5;
        
                    //to keep bottom part of mesh at its position
                    float smoothDeformation = smoothstep(_MeshDeformationLimitLow, _MeshDeformationLimitTop, o.uv.y);
                    float distortion = smoothDeformation * noise;
                    positionWorldSpace.xz += distortion * _WindStrength * normalize(_WindSpeed);
                }
                
                //apply distortion
                o.vertex = mul(UNITY_MATRIX_VP, float4(positionWorldSpace, 1));
                UNITY_TRANSFER_FOG(o,o.vertex);
    
                return o;
            }

            fixed4 frag (v2f i) : SV_Target
            {
                float4 col = lerp(_PrimaryCol, _SecondaryCol, i.uv.y);

                //from https://github.com/GarrettGunnell/Grass/blob/main/Assets/Shaders/ModelGrass.shader
                float light = clamp(dot(LightDir, normalize(float3(0, 1, 0))), 0 , 1);
                float4 ao = lerp(_AOColor, 1.0f, i.uv.y);
                float4 tip = lerp(0.0f, _TipColor, i.uv.y * i.uv.y * (1.0f + _Scale));
                float4 grassColor = (col + tip) * ao; // * light; // light needs to be fixed

                // apply fog
                UNITY_APPLY_FOG(i.fogCoord, col);
                return grassColor;
            }
            ENDCG
        }
    }
}
