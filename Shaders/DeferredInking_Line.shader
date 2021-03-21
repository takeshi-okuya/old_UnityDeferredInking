Shader "DeferredInking/Line"
{
    Properties
    {
        [Enum(Off, 0, Front, 1, Back, 2)] _Cull("Culling", INT) = 2
        _Color("Color", Color) = (0, 0, 0, 1)

        [Header(Outline Width)]
        _OutlineWidth("Outline Width (x0.1%)", FLOAT) = 2.0
        [Toggle] _Width_By_Distance("Width by Distance", Float) = 0
        [Toggle] _Width_By_FoV("Width by FoV", Float) = 0
        _MinWidth("Min Width", FLOAT) = 0.5
        _MaxWidth("Max Width", FLOAT) = 4.0

        [Header(Detection)]
        [Enum(Off, 255, Sufficiency, 0, Necessary, 1, Not, 2)] _DifferentModelID("Different Model ID", INT) = 0
        [Enum(Off, 255, Sufficiency, 0, Necessary, 1, Not, 2)] _DifferentMeshID("Different Mesh ID", INT) = 0
        [Space]
        [Enum(Off, 255, Sufficiency, 0, Necessary, 1, Not, 2)] _Use_Depth("Use Depth", INT) = 255
        _DepthThreshold("Threshold_Depth", FLOAT) = 2.0
        [Space]
        [Enum(Off, 255, Sufficiency, 0, Necessary, 1, Not, 2)] _Use_Normal("Use Normal", INT) = 255
        _NormalThreshold("Threshold_Normal", Range(-1, 1)) = 0.5
        _DepthRange("Depth_Range", FLOAT) = 0.2
        [Space]
        [Toggle] _Fill_Corner("Fill Corner", Float) = 0
    }
    SubShader
    {
        Tags { "RenderType" = "Opaque" "LineType" = "DeferredInking" }
        LOD 100

        Pass
        {
            CGPROGRAM
            #pragma vertex vert
            #pragma geometry geom
            #pragma fragment frag

            #include "UnityCG.cginc"

            #pragma multi_compile _ _FILL_CORNER_ON

            struct appdata
            {
                float4 vertex : POSITION;
                float3 normal : NORMAL;
            };

            struct v2g
            {
                float4 vertex : POSITION0;
                float2 projXY : TEXCOORD0;
                float4 viewPos_width : TEXCOORD1; //xyz: viewPos, w: width
                float3 normal : NORMAL0;
            };

            struct g2f
            {
                float4 vertex : SV_POSITION;
                noperspective float2 centerScreenPosXY : TEXCOORD1;
                float centerViewPosZ : TEXCOORD2;
                float3 normal : TEXCOORD3;

                #ifdef _FILL_CORNER_ON
                float2 corner : TEXCOORD4; //x:radius, y:isCorner(1 or 0).
                #endif
            };

            fixed4 _Color;

            float _OutlineWidth;
            float _Width_By_Distance;
            float _Width_By_FoV;
            float _MinWidth;
            float _MaxWidth;

            int _Cull;

            int _DifferentModelID;
            int _DifferentMeshID;

            int _Use_Depth;
            float _DepthThreshold;

            int _Use_Normal;
            float _NormalThreshold;
            float _DepthRange;

            Texture2D _GBuffer;
            float4 _GBuffer_TexelSize;
            Texture2D _GBufferDepth;
            SamplerState my_point_clamp_sampler;

            float2 _ID; // (ModelID, MeshID)

            float compWidth(float distance)
            {
                float width = _OutlineWidth;
                width = lerp(width, width / distance, _Width_By_Distance);
                width = lerp(width, width * unity_CameraProjection[1][1] / 4.167f, _Width_By_FoV); //4.167: cot(27deg/2). 27deg: 50mm

                if (_Width_By_Distance == 1.f || _Width_By_FoV == 1.f)
                {
                    width = clamp(width, _MinWidth, _MaxWidth);
                }

                return width * 0.001f;
            }

            v2g vert(appdata v)
            {
                v2g o;
                o.vertex = UnityObjectToClipPos(v.vertex);
                o.projXY = o.vertex.xy / o.vertex.w;
                o.viewPos_width.xyz = UnityObjectToViewPos(v.vertex);
                o.viewPos_width.w = compWidth(-o.viewPos_width.z);

                o.normal = COMPUTE_VIEW_NORMAL;

                return o;
            }

            bool isFrontFace(v2g input[3])
            {
                float3 v01 = float3(input[1].projXY - input[0].projXY, 0);
                float3 v02 = float3(input[2].projXY - input[0].projXY, 0);
                float c = cross(v01, v02).z;

                #ifdef UNITY_REVERSED_Z
                    return c >= 0;
                #else
                    return c <= 0;
                #endif
            }

            bool culling(v2g input[3])
            {
                if (_Cull == 0) { return false; } // 0: Off

                bool frontFace = isFrontFace(input);
                bool frontCull = _Cull == 1; // 1: Front, 2:Back
                return frontFace == frontCull;
            }

            void compDirection(v2g p1, v2g p2, float aspect, out float2 v12, out float2 right)
            {
                v12 = p2.projXY - p1.projXY;
                v12.x *= aspect;
                v12 = normalize(v12);
                right = float2(-v12.y, v12.x);

                v12.x /= aspect;
                right.x /= aspect;
            }

            g2f generatePoint(v2g p, float2 direction)
            {
                g2f o;
                float4 translate = float4(p.viewPos_width.w * direction * p.vertex.w, 0, 0);
                o.vertex = p.vertex + translate;

                o.centerScreenPosXY = (p.projXY + 1.0f) * 0.5f;
                #if UNITY_UV_STARTS_AT_TOP == 1
                    o.centerScreenPosXY.y = 1 - o.centerScreenPosXY.y;
                #endif

                o.centerViewPosZ = -p.viewPos_width.z;

                o.normal = p.normal;

                #ifdef _FILL_CORNER_ON
                    o.corner = float2(p.viewPos_width.w * 0.5f, 0);
                #endif

                return o;
            }

            void appendTSLine(in g2f dst[4], float2 direction12, float p1Width, inout TriangleStream<g2f> ts)
            {
                #ifdef _FILL_CORNER_ON
                    g2f o = dst[0];
                    o.corner.y = 1;
                    o.vertex.xy -= direction12 * p1Width * o.vertex.w;
                    ts.Append(o);
                    o.vertex.xy = dst[1].vertex.xy - direction12 * p1Width * o.vertex.w;
                    ts.Append(o);
                #endif

                [unroll]
                for (int i = 0; i < 4; i++)
                {
                    ts.Append(dst[i]);
                }

                ts.RestartStrip();
            }

            void generateLine(v2g p1, v2g p2, float aspect, inout TriangleStream<g2f> ts)
            {
                float2 v12, right;
                compDirection(p1, p2, aspect, v12, right);

                g2f dst[4];
                dst[0] = generatePoint(p1, right);
                dst[1] = generatePoint(p1, -right);
                dst[2] = generatePoint(p2, right);
                dst[3] = generatePoint(p2, -right);

                appendTSLine(dst, v12, p1.viewPos_width.w, ts);
            }

        #ifdef _FILL_CORNER_ON
            [maxvertexcount(18)]
        #else
            [maxvertexcount(12)]
        #endif
            void geom(triangle v2g input[3], inout TriangleStream<g2f> ts)
            {
                #if !defined(_CULL_OFF)
                    if (culling(input) == true) return;
                #endif

                float aspect = (-UNITY_MATRIX_P[1][1]) / UNITY_MATRIX_P[0][0];

                generateLine(input[0], input[1], aspect, ts);
                generateLine(input[1], input[2], aspect, ts);
                generateLine(input[2], input[0], aspect, ts);
            }

        #ifdef _FILL_CORNER_ON
            void clipCorner(g2f i)
            {
                float radius = i.corner.x;

                float2 vpos = (i.vertex.xy + 0.5f) / _ScreenParams.xy;
                float2 sub = i.centerScreenPosXY - vpos;
                float aspect = (-UNITY_MATRIX_P[1][1]) / UNITY_MATRIX_P[0][0];
                sub.x *= aspect;

                clip((i.corner.y == 0 || dot(sub, sub) < radius * radius) - 0.1);
            }
        #endif

            float decodeGBufferDepth(float2 uv)
            {
                float gbDepth = _GBufferDepth.Sample(my_point_clamp_sampler, uv).x;

                if (unity_OrthoParams.w == 1.0f) { //ORTHO
                    #if !defined(UNITY_REVERSED_Z)
                        gbDepth = 2 * gbDepth - 1;
                    #endif
                    return -(gbDepth - UNITY_MATRIX_P[2][3]) / UNITY_MATRIX_P[2][2];
                } else {
                    return DECODE_EYEDEPTH(gbDepth);
                }
            }

            bool isSameID(float2 id)
            {
                float2 sub = abs(id * 255.0f - _ID);
                return sub.x + sub.y < 0.1f;
            }

            void sampleGBuffers(float2 uv, out bool3x3 isSameModelIDs, out bool3x3 isSameMaterialIDs, out float2 normals[3][3])
            {
                [unroll]
                for (int y = -1; y <= 1; y++)
                {
                    [unroll]
                    for (int x = -1; x <= 1; x++)
                    {
                        float2 _uv = uv + float2(x, y) * _GBuffer_TexelSize;
                        float4 g = _GBuffer.Sample(my_point_clamp_sampler, _uv);

                        float2 sub = abs(g.zw * 255.0f - _ID);
                        isSameModelIDs[y + 1][x + 1] = sub.x <= 0.1f;
                        isSameMaterialIDs[y + 1][x + 1] = sub.y <= 0.1f;

                        normals[y + 1][x + 1] = g.xy;
                    }
                }
            }

            float3x3 sampleDepths(float2 uv)
            {
                float3x3 dst;

                [unroll]
                for (int y = -1; y <= 1; y++)
                {
                    [unroll]
                    for (int x = -1; x <= 1; x++)
                    {
                        float2 _uv = uv + float2(x, y) * _GBuffer_TexelSize;
                        dst[y + 1][x + 1] = decodeGBufferDepth(_uv);
                    }
                }

                return dst;
            }

            bool detectNormal(float3 centerNormal, float centerDepth, float2 normals[3][3], float3x3 depths)
            {
                bool isDraw = false;
                float d = centerDepth - _DepthRange;

                for (int y = 0; y < 3; y++)
                {
                    for (int x = 0; x < 3; x++)
                    {
                        float3 n = DecodeViewNormalStereo(float4(normals[y][x], 0, 0));
                        isDraw = isDraw ||
                            (
                                (dot(centerNormal, n) < _NormalThreshold) &&
                                (d < depths[y][x])
                            );
                    }
                }

                return isDraw;
            }

            void clipDepthID(float2 vposXY, float centerZ)
            {
                float2 uv = (vposXY + 0.5) / _ScreenParams.xy;
                float2 id = _GBuffer.Sample(my_point_clamp_sampler, uv).zw;
                float depth = decodeGBufferDepth(uv);
                bool isDraw = isSameID(id) || centerZ < depth;

                clip(isDraw - 0.1f);
            }

            void addConditions(int condition, bool isFill, inout int3 isDrawTimes, inout int3 isDrawTrues)
            {
                if (condition == 0)
                {
                    isDrawTimes[0] += 1;
                    isDrawTrues[0] += isFill;
                }
                else if (condition == 1)
                {
                    isDrawTimes[1] += 1;
                    isDrawTrues[1] += isFill;
                }
                else
                {
                    isDrawTimes[2] += 1;
                    isDrawTrues[2] += isFill;
                }
            }

            fixed4 frag(g2f i) : SV_Target
            {
                #ifdef _FILL_CORNER_ON
                    clipCorner(i);
                #endif

                float2 uv = i.centerScreenPosXY;
                bool3x3 isSameModelIDs, isSameMeshIDs;
                float2 normals[3][3];
                sampleGBuffers(uv, isSameModelIDs, isSameMeshIDs, normals);

                bool3x3 isSameIDs = isSameModelIDs && isSameMeshIDs;
                clip(any(isSameIDs) - 0.1f);
                clipDepthID(i.vertex.xy, i.centerViewPosZ);

                bool isDraw = false;
                float3x3 depths = sampleDepths(uv);

                int3 isDrawTimes = int3(0, 0, 0);
                int3 isDrawTrues = int3(0, 0, 0);

                bool3x3 isDeeps = depths > i.centerViewPosZ;
                if (_DifferentModelID != 255)
                {
                    bool isFill = any(!isSameModelIDs && isDeeps);
                    addConditions(_DifferentModelID, isFill, isDrawTimes, isDrawTrues);
                }

                if (_DifferentMeshID != 255)
                {
                    bool isFill = any(!isSameMeshIDs && isDeeps);
                    addConditions(_DifferentMeshID, isFill, isDrawTimes, isDrawTrues);
                }

                if (_Use_Depth != 255)
                {
                    bool isFill = any(depths - i.centerViewPosZ > _DepthThreshold);
                    addConditions(_Use_Depth, isFill, isDrawTimes, isDrawTrues);
                }

                if (_Use_Normal != 255)
                {
                    bool isFill = detectNormal(i.normal, i.centerViewPosZ, normals, depths);
                    addConditions(_Use_Normal, isFill, isDrawTimes, isDrawTrues);
                }

                if (isDrawTrues.x + isDrawTrues.y == 0 || isDrawTimes.y != isDrawTrues.y || isDrawTrues.z > 0)
                {
                    clip(-1);
                }
                return _Color;
            }
            ENDCG
        }
    }

    FallBack "Diffuse"
}
