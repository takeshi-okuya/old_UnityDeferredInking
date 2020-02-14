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
		[Toggle] _Use_Curvature("Use Curvature", Float) = 0
    }
    SubShader
    {
        Tags { "RenderType"="Opaque" "LineType" = "DeferredInking" }
        LOD 100

        Pass
        {
            CGPROGRAM
            #pragma vertex vert
            #pragma geometry geom
            #pragma fragment frag

            #include "UnityCG.cginc"
			#include "Curvature.cginc"

            #pragma multi_compile _CULL_OFF _CULL_FRONT _CULL_BACK
            #pragma multi_compile _ _WIDTH_BY_DISTANCE_ON
            #pragma multi_compile _ _WIDTH_BY_FOV_ON
            #pragma multi_compile _ _USE_OBJECT_ID_ON
            #pragma multi_compile _ _USE_DEPTH_ON
            #pragma multi_compile _ _USE_NORMAL_ON
			#pragma multi_compile _ _USE_CURVATURE_ON
			#pragma multi_compile _ _ORTHO_ON

            struct appdata
            {
                float4 vertex : POSITION;
                #ifdef _USE_NORMAL_ON
                float3 normal : NORMAL;
                #endif
				uint id : SV_VertexID;
            };

            struct v2g
            {
                float4 vertex : POSITION0;

                #if !defined(_ORTHO_ON)
                float2 projXY : POSITION1;
                #endif

                #ifdef _USE_NORMAL_ON
                float3 normal : TEXCOORD0;
                #endif

				float width : POSITION2;
            };

            struct g2f
            {
                float4 vertex : SV_POSITION;
                float3 center : POSITION1;
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

            Texture2D _GBuffer;
            float4 _GBuffer_TexelSize;
            Texture2D _GBufferDepth;
            SamplerState my_point_clamp_sampler;

            float2 _ID; // (ModelID, MeshID)

            v2g vert (appdata v)
            {
                v2g o;
                o.vertex = UnityObjectToClipPos(v.vertex);

                #ifdef _ORTHO_ON
                    o.vertex.w = -UnityObjectToViewPos(v.vertex).z;
                #else
                    o.projXY = o.vertex.xy / o.vertex.w;
                #endif

                #ifdef _USE_NORMAL_ON
                    o.normal = COMPUTE_VIEW_NORMAL;
                #endif

				o.width = compCurvatureWidth(v.id);

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

            void appendPoint(v2g p, float2 translate, inout g2f o, inout TriangleStream<g2f> ts)
            {
                #ifdef _ORTHO_ON
                    float2 xy = p.vertex.xy + translate;
                    o.vertex = float4(xy, p.vertex.z, 1);
                    o.center = p.vertex.xyw;
                #else
                    float2 xy = (p.projXY + translate) * p.vertex.w;
                    o.vertex = float4(xy, p.vertex.zw);
                    o.center = float3(p.projXY, p.vertex.w);
                #endif

					o.vertex.z += o.vertex.w * 0.002;

                #ifdef _USE_NORMAL_ON
                    o.normal = p.normal;
                #endif

                ts.Append(o);
            }

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

            void generateLine(v2g p1, v2g p2, float aspect, inout TriangleStream<g2f> ts)
            {
                #ifdef _ORTHO_ON
                    float2 v12 = p2.vertex.xy - p1.vertex.xy;
                #else
                    float2 v12 = p2.projXY - p1.projXY;
                #endif

                v12.x *= aspect;
                v12 = normalize(v12);
                float2 right = float2(-v12.y, v12.x);
                right.x /= aspect;

                float2 translate1 = compWidth(p1.vertex.w) * right * p1.width;
                float2 translate2 = compWidth(p2.vertex.w) * right * p2.width;

                g2f o;

                appendPoint(p1, -translate1, o, ts);
                appendPoint(p2, -translate2, o, ts);
                appendPoint(p1, translate1, o, ts);
                appendPoint(p2, translate2, o, ts);
                ts.RestartStrip();
            }

            [maxvertexcount(12)]
            void geom(triangle v2g input[3], uint pid : SV_PrimitiveID, inout TriangleStream<g2f> ts)
            {
                #if !defined(_CULL_OFF)
                    if (culling(input) == true) return;
                #endif

                float aspect = (-UNITY_MATRIX_P[1][1]) / UNITY_MATRIX_P[0][0];

                generateLine(input[0], input[1], aspect, ts);
                generateLine(input[1], input[2], aspect, ts);
                generateLine(input[2], input[0], aspect, ts);
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

			bool compDepths(float x, float y, float centerDepth, float2 centerUV)
			{
				float2 _uv = centerUV + float2(x, y) * _GBuffer_TexelSize;
				float depth = decodeGBufferDepth(_uv);
				return abs(depth - centerDepth) > _DepthThreshold;
			}

			bool detectDepth(float2 uv)
			{
				bool isDraw = false;
				float centerDepth = decodeGBufferDepth(uv);

				isDraw = isDraw || compDepths(-1, -1, centerDepth, uv);
				isDraw = isDraw || compDepths(-1, 0, centerDepth, uv);
				isDraw = isDraw || compDepths(-1, 1, centerDepth, uv);
				isDraw = isDraw || compDepths(0, -1, centerDepth, uv);
				isDraw = isDraw || compDepths(0, 1, centerDepth, uv);
				isDraw = isDraw || compDepths(1, -1, centerDepth, uv);
				isDraw = isDraw || compDepths(1, 0, centerDepth, uv);
				isDraw = isDraw || compDepths(1, 1, centerDepth, uv);

				return isDraw;
			}

			float3 sampleNormal(float2 uv)
			{
				float4 g = _GBuffer.Sample(my_point_clamp_sampler, uv);
				return DecodeViewNormalStereo(float4(g.xy, 0, 0));
			}

			bool compNormals(float x, float y, float3 centerNormal, float2 centerUV)
			{
				float2 _uv = centerUV + float2(x, y) * _GBuffer_TexelSize;
				float3 n = sampleNormal(_uv);
				return dot(centerNormal, n) < _NormalThreshold;
			}

			bool detectNormal(float2 uv)
			{
				bool isDraw = false;
				float3 centerNormal = sampleNormal(uv);

				isDraw = isDraw || compNormals(-1, -1, centerNormal, uv);
				isDraw = isDraw || compNormals(-1, 0, centerNormal, uv);
				isDraw = isDraw || compNormals(-1, 1, centerNormal, uv);
				isDraw = isDraw || compNormals(0, -1, centerNormal, uv);
				isDraw = isDraw || compNormals(0, 1, centerNormal, uv);
				isDraw = isDraw || compNormals(1, -1, centerNormal, uv);
				isDraw = isDraw || compNormals(1, 0, centerNormal, uv);
				isDraw = isDraw || compNormals(1, 1, centerNormal, uv);

				return isDraw;
			}

            fixed4 frag (g2f i) : SV_Target
            {
                float2 uv = (i.center.xy + 1.0f) * 0.5f;
                #if UNITY_UV_STARTS_AT_TOP == 1
                    uv.y = 1 - uv.y;
                #endif

                bool isDraw = false;

                #ifdef _USE_DEPTH_ON
					isDraw = isDraw || detectDepth(uv);
				#endif

                #ifdef _USE_NORMAL_ON
                    isDraw = isDraw || detectNormal(uv);
                #endif

                clip(isDraw - 0.1f);

                return _Color;
            }
            ENDCG
        }
    }

    FallBack "Diffuse"
}
