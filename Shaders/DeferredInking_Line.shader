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
    }
    SubShader
    {
        Tags { "RenderType"="Opaque" "LineType" = "DeferredInking" }
        LOD 100

        Pass
        {
            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag

            #include "UnityCG.cginc"

            #pragma multi_compile _CULL_OFF _CULL_FRONT _CULL_BACK
            #pragma multi_compile _ _WIDTH_BY_DISTANCE_ON
            #pragma multi_compile _ _WIDTH_BY_FOV_ON
            #pragma multi_compile _ _USE_OBJECT_ID_ON
            #pragma multi_compile _ _USE_DEPTH_ON
            #pragma multi_compile _ _USE_NORMAL_ON
            #pragma multi_compile _ _ORTHO_ON

            struct v2f
            {
                float4 vertex : SV_POSITION;
                float4 center : POSITION1;
                #ifdef _USE_NORMAL_ON
                float3 normal : TEXCOORD0;
                #endif
            };

            fixed4 _Color;

            float _OutlineWidth;
            float _MinWidth;
            float _MaxWidth;

            float _DepthThreshold;
            float _NormalThreshold;
            float _DepthRange;

            StructuredBuffer<float3> _Vertices;
            StructuredBuffer<float3> _Normals;

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

            v2f vert (float4 idxs : POSITION0)
            {
                v2f o;

                float3 local1 = _Vertices[asint(idxs.x)];
                float3 local2 = _Vertices[asint(idxs.y)];
                float4 proj1 = UnityObjectToClipPos(local1);
                float4 proj2 = UnityObjectToClipPos(local2);

                float2 v12 = proj2.xy / proj2.w - proj1.xy / proj1.w;

                float aspect = (-UNITY_MATRIX_P[1][1]) / UNITY_MATRIX_P[0][0];
                v12.x *= aspect;
                v12 = normalize(v12);
                float2 right = idxs.z * float2(-v12.y, v12.x);
                right.x /= aspect;

                float2 translate = compWidth(proj1.w) * right;

                o.vertex = proj1;
                o.vertex.xy += translate * proj1.w;
                o.center = proj1;

                #ifdef _ORTHO_ON
                    //o.vertex.w = -UnityObjectToViewPos(vertex).z;
                #else
                    //o.projXY = o.vertex.xy / o.vertex.w;
                #endif

                #ifdef _USE_NORMAL_ON
                    o.normal = mul((float3x3)UNITY_MATRIX_IT_MV, _Normals[asint(idxs.x)]);
                #endif

                return o;
            }

            float decodeGBufferDepth(float2 uv)
            {
                float gbDepth = _GBufferDepth.Sample(my_point_clamp_sampler, uv).x;

                #ifdef _ORTHO_ON
                    #if !defined(UNITY_REVERSED_Z)
                        gbDepth =  2 * gbDepth - 1;
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

            fixed4 frag (v2f i) : SV_Target
            {
                float3 center = float3(i.center.xy / i.center.w, i.center.w);
                float2 uv = (center.xy + 1.0f) * 0.5f;
                #if UNITY_UV_STARTS_AT_TOP == 1
                    uv.y = 1 - uv.y;
                #endif

                bool3x3 isSameIDs;
                #ifdef _USE_NORMAL_ON
                    float2 normals[3][3];
                    sampleGBuffers(uv, isSameIDs, normals);
                #else
                    sampleGBuffers(uv, isSameIDs);
                #endif

                clip(any(isSameIDs) - 0.1f);
                clipDepthID(i.vertex.xy, center.z);

                bool isDraw = false;
                float3x3 depths = sampleDepths(uv);

                #ifdef _USE_OBJECT_ID_ON
                    isDraw = isDraw || any(!isSameIDs && (depths > center.z));
                #endif

                #ifdef _USE_DEPTH_ON
                    isDraw = isDraw || any(depths - center.z > _DepthThreshold);
                #endif

                #ifdef _USE_NORMAL_ON
                    isDraw = isDraw || detectNormal(i.normal, center.z, normals, depths);
                #endif

                clip(isDraw - 0.1f);

                return _Color;
            }
            ENDCG
        }
    }

    FallBack "Diffuse"
}
