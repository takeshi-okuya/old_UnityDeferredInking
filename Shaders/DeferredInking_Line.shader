Shader "DeferredInking/Line"
{
    Properties
    {
        _Color("Color", Color) = (0, 0, 0, 1)
        _OutlineWidth("Outline Width", FLOAT) = 0.003
        [KeywordEnum(Off, Front, Back)] _Cull("Culling", Float) = 0
        [Space]
        [Toggle] _Use_Object_ID("Use Object ID", Float) = 1
        [Space]
        [Toggle] _Use_Depth("Use Depth", Float) = 0
        _DepthThreshold("Threshold_Depth", FLOAT) = 2.0
        [Space]
        [Toggle] _Use_Normal("Use Normal", Float) = 0
        _NormalThreshold("Threshold_Normal", Range(-1, 1)) = 0.5
        _DepthRange("Depth_Range", FLOAT) = 0.2
    }
    SubShader
    {
        Tags { "RenderType"="Opaque" }
        LOD 100

        Pass
        {
            CGPROGRAM
            #pragma vertex vert
            #pragma geometry geom
            #pragma fragment frag

            #include "UnityCG.cginc"

            #pragma multi_compile _CULL_OFF _CULL_FRONT _CULL_BACK
            #pragma multi_compile _ _USE_OBJECT_ID_ON
            #pragma multi_compile _ _USE_DEPTH_ON
            #pragma multi_compile _ _USE_NORMAL_ON

            struct appdata
            {
                float4 vertex : POSITION;
                #ifdef _USE_NORMAL_ON
                float3 normal : NORMAL;
                #endif
            };

            struct v2g
            {
                float4 vertex : SV_POSITION;
                float2 projXY : POSITION1;
                #ifdef _USE_NORMAL_ON
                float3 normal : TEXCOORD0;
                #endif
            };

            struct g2f
            {
                float4 vertex : SV_POSITION;
                float4 center : POSITION1;
                #ifdef _USE_NORMAL_ON
                float3 normal : TEXCOORD0;
                #endif
            };

            fixed4 _Color;
            float _OutlineWidth;
            float _DepthThreshold;
            float _NormalThreshold;
            float _DepthRange;

            Texture2D _GBuffer;
            float4 _GBuffer_TexelSize;
            Texture2D _GBufferDepth;
            SamplerState my_point_clamp_sampler;

            sampler2D _CameraDepthTexture;
            sampler2D _CameraDepthNormalsTexture;
            float4 _CameraDepthNormalsTexture_TexelSize;

            float modelID;
            float meshID;

            v2g vert (appdata v)
            {
                v2g o;
                o.vertex = UnityObjectToClipPos(v.vertex);
                o.projXY = o.vertex.xy / o.vertex.w;

                #ifdef _USE_NORMAL_ON
                    o.normal = COMPUTE_VIEW_NORMAL;
                #endif

                return o;
            }

            bool isFrontFace(triangle v2g input[3])
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

            bool culling(bool frontFace)
            {
                #ifdef _CULL_FRONT
                    return frontFace;
                #elif _CULL_BACK
                    return !frontFace;
                #endif
            }

            #ifdef _USE_NORMAL_ON
            void reverseNormals(inout v2g input[3], bool frontFace)
            {
                #ifdef _CULL_OFF
                    float direction = (float)frontFace * 2.0f - 1.0f;
                    input[0].normal *= direction;
                    input[1].normal *= direction;
                    input[2].normal *= direction;
                #elif _CULL_FRONT
                    input[0].normal = -input[0].normal;
                    input[1].normal = -input[1].normal;
                    input[2].normal = -input[2].normal;
                #endif
            }
            #endif

            void appendPoint(v2g p, float2 translate, inout g2f o, inout TriangleStream<g2f> ts)
            {
                float2 xy = (p.projXY + translate) * p.vertex.w;
                o.vertex = float4(xy, p.vertex.zw);
                o.center = p.vertex;

                #ifdef _USE_NORMAL_ON
                    o.normal = p.normal;
                #endif

                ts.Append(o);
            }

            void generateLine(v2g p1, v2g p2, float aspect, inout TriangleStream<g2f> ts)
            {
                float2 v12 = p2.projXY - p1.projXY;
                v12.x *= aspect;
                v12 = normalize(v12);
                float2 right = float2(-v12.y, v12.x);
                float2 translate = _OutlineWidth * right;
                translate.x /= aspect;

                g2f o;

                appendPoint(p1, -translate, o, ts);
                appendPoint(p2, -translate, o, ts);
                appendPoint(p1, translate, o, ts);
                appendPoint(p2, translate, o, ts);
                ts.RestartStrip();
            }

            [maxvertexcount(12)]
            void geom(triangle v2g input[3], uint pid : SV_PrimitiveID, inout TriangleStream<g2f> ts)
            {
                #if !defined(_CULL_OFF) || defined(_USE_NORMAL_ON)
                    bool frontFace = isFrontFace(input);
                #endif

                #if !defined(_CULL_OFF)
                    if (culling(frontFace) == true) return;
                #endif

                #if defined(_USE_NORMAL_ON)
                    reverseNormals(input, frontFace);
                #endif

                float aspect = (-UNITY_MATRIX_P[1][1]) / UNITY_MATRIX_P[0][0];

                generateLine(input[0], input[1], aspect, ts);
                generateLine(input[1], input[2], aspect, ts);
                generateLine(input[2], input[0], aspect, ts);
            }

            bool depthSobel(float3x3 depths)
            {
                float2 sumsX = float2(1, -1) * depths[0].xz + float2(2, -2) * depths[1].xz + float2(1, -1) * depths[2].xz;
                float lx = sumsX.x + sumsX.y;

                float3 sumsY = float3(1, 2, 1) * depths[0] + float3(-1, -2, -1) * depths[2];
                float ly = sumsY.x + sumsY.y + sumsY.z;

                return sqrt(lx * lx + ly * ly) >= _DepthThreshold;
            }

            bool3x3 compareSameIDs(float2 uv)
            {
                bool3x3 dst;
                float2 selfID = float2(modelID, meshID);

                for (int y = -1; y <= 1; y++)
                {
                    for (int x = -1; x <= 1; x++)
                    {
                        float2 _uv = uv + float2(x, y) * _GBuffer_TexelSize;
                        float4 g = _GBuffer.Sample(my_point_clamp_sampler, _uv);
                        float2 sub = abs(g.xy * 255.0f - selfID);
                        dst[y + 1][x + 1] = sub.x + sub.y < 0.1f;
                    }
                }

                return dst;
            }

            float3x3 sampleDepths(float2 uv)
            {
                float3x3 dst;

                for (int y = -1; y <= 1; y++)
                {
                    for (int x = -1; x <= 1; x++)
                    {
                        float2 _uv = uv + float2(x, y) * _GBuffer_TexelSize;
                        dst[y + 1][x + 1] = DECODE_EYEDEPTH(_GBufferDepth.Sample(my_point_clamp_sampler, _uv)).x;
                    }
                }

                return dst;
            }

            bool detectDifferentID(bool3x3 isSameIDs, float3x3 depths, float centerDepth)
            {
                bool isDraw = false;

                for (int y = 0; y <= 2; y++)
                {
                    for (int x = 0; x <= 2; x++)
                    {
                        bool _isDraw = !isSameIDs[y][x] && (centerDepth < depths[y][x]);
                        isDraw = isDraw || _isDraw;
                    }
                }

                return isDraw;
            }

            void sampleNormals(out float4 dst[3][3], float2 uv)
            {
                for (int y = -1; y <= 1; y++)
                {
                    for (int x = -1; x <= 1; x++)
                    {
                        float2 _uv = uv + float2(x, y) * _CameraDepthNormalsTexture_TexelSize;
                        float4 depthNormal = tex2D(_CameraDepthNormalsTexture, _uv);
                        float depth;
                        float3 normal;
                        DecodeDepthNormal(depthNormal, depth, normal);
                        dst[y + 1][x + 1] = float4(normal, depth);
                    }
                }
            }

            bool detectNormal(float3 centerNormal, float4 depthNormals[3][3], float centerDepth)
            {
                bool isDraw = false;
                float d = centerDepth - _DepthRange;
                d = d * _ProjectionParams.w;

                for (int y = 0; y < 3; y++)
                {
                    for (int x = 0; x < 3; x++)
                    {
                        isDraw = isDraw ||
                            (
                                (dot(centerNormal, depthNormals[y][x].xyz) < _NormalThreshold) && 
                                (d < depthNormals[y][x].w)
                            );
                    }
                }

                return isDraw;
            }

            fixed4 frag (g2f i) : SV_Target
            {
                float2 uv = (i.center.xy / i.center.w + 1.0f) * 0.5f;
                #if UNITY_UV_STARTS_AT_TOP == 1
                    uv.y = 1 - uv.y;
                #endif

                bool3x3 isSameIDs = compareSameIDs(uv);
                clip(any(isSameIDs) - 0.1f);

                bool isDraw = false;
                float3x3 depths = sampleDepths(uv);

                #ifdef _USE_OBJECT_ID_ON
                    isDraw = isDraw || detectDifferentID(isSameIDs, depths, i.center.w);
                #endif

                #ifdef _USE_DEPTH_ON
                    isDraw = isDraw || depthSobel(depths);
                #endif

                #ifdef _USE_NORMAL_ON
                    float4 normals[3][3];
                    sampleNormals(normals, uv);
                    isDraw = isDraw || detectNormal(i.normal, normals, i.center.w);
                #endif

                clip(isDraw - 0.1f);

                return _Color;
            }
            ENDCG
        }
    }

    FallBack "Diffuse"
}
