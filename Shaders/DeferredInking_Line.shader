Shader "DeferredInking/Line"
{
    Properties
    {
        [KeywordEnum(Off, Front, Back)] _Cull("Culling", Float) = 2
        _Color("Color", Color) = (0, 0, 0, 1)

        [Header(Outline Width)]
        _OutlineWidth("Outline Width (x0.1%)", FLOAT) = 2.0
        [Toggle] _Width_By_Distance("Width by Distance", Float) = 0
        [Toggle] _Width_By_FoV("Width by FoV", Float) = 0
        _MinWidth("Min Width", FLOAT) = 0.5
        _MaxWidth("Max Width", FLOAT) = 4.0

        [Header(Detection)]
        [Toggle] _Use_Object_ID("Use Object ID", Float) = 1
        [Space]
        [Toggle] _Use_Depth("Use Depth", Float) = 0
        _DepthThreshold("Threshold_Depth", FLOAT) = 2.0
        [Space]
        [Toggle] _Use_Normal("Use Normal", Float) = 0
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

            #pragma multi_compile _CULL_OFF _CULL_FRONT _CULL_BACK
            #pragma multi_compile _ _WIDTH_BY_DISTANCE_ON
            #pragma multi_compile _ _WIDTH_BY_FOV_ON
            #pragma multi_compile _ _USE_OBJECT_ID_ON
            #pragma multi_compile _ _USE_DEPTH_ON
            #pragma multi_compile _ _USE_NORMAL_ON
            #pragma multi_compile _ _FILL_CORNER_ON
            #pragma multi_compile _ _ORTHO_ON

            struct appdata
            {
                float4 vertex : POSITION;
                #ifdef _USE_NORMAL_ON
                float3 normal : NORMAL;
                #endif
            };

            struct v2g
            {
                float4 vertex : POSITION0;
                float width : TEXCOORD0;

                #if !defined(_ORTHO_ON)
                float2 projXY : POSITION1;
                #endif

                #ifdef _USE_NORMAL_ON
                float3 normal : NORMAL0;
                #endif
            };

            struct g2f
            {
                float4 vertex : SV_POSITION;
                noperspective float2 centerScreenPosXY : TEXCOORD1;
                float centerViewPosZ : TEXCOORD2;

                #ifdef _USE_NORMAL_ON
                float3 normal : TEXCOORD3;
                #endif
                #ifdef _FILL_CORNER_ON
                float2 corner : TEXCOORD4; //x:radius, y:isCorner(1 or 0).
                #endif
            };

            fixed4 _Color;

            float _OutlineWidth;
            float _MinWidth;
            float _MaxWidth;

            float _DepthThreshold;
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

                #ifdef _WIDTH_BY_DISTANCE_ON
                    width /= distance;
                #endif

                #ifdef _WIDTH_BY_FOV_ON
                    width *= unity_CameraProjection[1][1] / 4.167;
                #endif

                #if defined(_WIDTH_BY_DISTANCE_ON) || defined(_WIDTH_BY_FOV_ON)
                    width = clamp(width, _MinWidth, _MaxWidth);
                #endif

                return width * 0.001f;
            }

            v2g vert(appdata v)
            {
                v2g o;
                o.vertex = UnityObjectToClipPos(v.vertex);

                #ifdef _ORTHO_ON
                    o.vertex.w = -UnityObjectToViewPos(v.vertex).z;
                #else
                    o.projXY = o.vertex.xy / o.vertex.w;
                #endif

                o.width = compWidth(o.vertex.w);

                #ifdef _USE_NORMAL_ON
                    o.normal = COMPUTE_VIEW_NORMAL;
                #endif

                return o;
            }

            bool culling(v2g input[3])
            {
                #ifdef _ORTHO_ON
                    float3 v01 = float3(input[1].vertex.xy - input[0].vertex.xy, 0);
                    float3 v02 = float3(input[2].vertex.xy - input[0].vertex.xy, 0);
                #else
                    float3 v01 = float3(input[1].projXY - input[0].projXY, 0);
                    float3 v02 = float3(input[2].projXY - input[0].projXY, 0);
                #endif
                float c = cross(v01, v02).z;

                bool isFrontFace;
                #ifdef UNITY_REVERSED_Z
                    isFrontFace = c >= 0;
                #else
                    isFrontFace = c <= 0;
                #endif

                #ifdef _CULL_FRONT
                    return isFrontFace;
                #elif _CULL_BACK
                    return !isFrontFace;
                #endif
            }

            void compDirection(v2g p1, v2g p2, float aspect, out float2 v12, out float2 right)
            {
                #ifdef _ORTHO_ON
                    v12 = p2.vertex.xy - p1.vertex.xy;
                #else
                    v12 = p2.projXY - p1.projXY;
                #endif

                v12.x *= aspect;
                v12 = normalize(v12);
                right = float2(-v12.y, v12.x);

                v12.x /= aspect;
                right.x /= aspect;
            }

            g2f generatePoint(v2g p, float2 direction)
            {
                g2f o;
                float2 translate = p.width * direction;

                #ifdef _ORTHO_ON
                    float2 xy = p.vertex.xy + translate;
                    o.vertex = float4(xy, p.vertex.z, 1);
                    o.centerScreenPosXY = (p.vertex.xy + 1.0f) * 0.5f;
                    o.centerViewPosZ = p.vertex.w;
                #else
                    float2 xy = (p.projXY + translate) * p.vertex.w;
                    o.vertex = float4(xy, p.vertex.zw);
                    o.centerScreenPosXY = (p.projXY + 1.0f) * 0.5f;
                    o.centerViewPosZ = p.vertex.w;
                #endif

                #if UNITY_UV_STARTS_AT_TOP == 1
                    o.centerScreenPosXY.y = 1 - o.centerScreenPosXY.y;
                #endif

                #ifdef _USE_NORMAL_ON
                    o.normal = p.normal;
                #endif

                #ifdef _FILL_CORNER_ON
                    o.corner = float2(p.width * 0.5f, 0);
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

                appendTSLine(dst, v12, p1.width, ts);
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

                #ifdef _ORTHO_ON
                    #if !defined(UNITY_REVERSED_Z)
                        gbDepth = 2 * gbDepth - 1;
                    #endif
                    return -(gbDepth - UNITY_MATRIX_P[2][3]) / UNITY_MATRIX_P[2][2];
                #else
                    return DECODE_EYEDEPTH(gbDepth);
                #endif
            }

            bool isSameID(float2 id)
            {
                float2 sub = abs(id * 255.0f - _ID);
                return sub.x + sub.y < 0.1f;
            }

        #ifdef _USE_NORMAL_ON
            void sampleGBuffers(float2 uv, out bool3x3 isSameIDs, out float2 normals[3][3])
        #else
            void sampleGBuffers(float2 uv, out bool3x3 isSameIDs)
        #endif
            {
                [unroll]
                for (int y = -1; y <= 1; y++)
                {
                    [unroll]
                    for (int x = -1; x <= 1; x++)
                    {
                        float2 _uv = uv + float2(x, y) * _GBuffer_TexelSize;
                        float4 g = _GBuffer.Sample(my_point_clamp_sampler, _uv);
                        isSameIDs[y + 1][x + 1] = isSameID(g.zw);

                        #ifdef _USE_NORMAL_ON
                            normals[y + 1][x + 1] = g.xy;
                        #endif
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

            fixed4 frag(g2f i) : SV_Target
            {
                #ifdef _FILL_CORNER_ON
                    clipCorner(i);
                #endif

                float2 uv = i.centerScreenPosXY;
                bool3x3 isSameIDs;
                #ifdef _USE_NORMAL_ON
                    float2 normals[3][3];
                    sampleGBuffers(uv, isSameIDs, normals);
                #else
                    sampleGBuffers(uv, isSameIDs);
                #endif

                clip(any(isSameIDs) - 0.1f);
                clipDepthID(i.vertex.xy, i.centerViewPosZ);

                bool isDraw = false;
                float3x3 depths = sampleDepths(uv);

                #ifdef _USE_OBJECT_ID_ON
                    isDraw = isDraw || any(!isSameIDs && (depths > i.centerViewPosZ));
                #endif

                #ifdef _USE_DEPTH_ON
                    isDraw = isDraw || any(depths - i.centerViewPosZ > _DepthThreshold);
                #endif

                #ifdef _USE_NORMAL_ON
                    isDraw = isDraw || detectNormal(i.normal, i.centerViewPosZ, normals, depths);
                #endif

                clip(isDraw - 0.1f);

                return _Color;
            }
            ENDCG
        }
    }

    FallBack "Diffuse"
}
