Shader "Hidden/ImageProcessingLine"
{
    Properties
    {
    }
    SubShader
    {
        // No culling or depth
        Cull Off ZWrite Off ZTest Always

        Pass
        {
            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag

            #include "UnityCG.cginc"

			#pragma multi_compile _ _ORTHO_ON

            struct appdata
            {
                float4 vertex : POSITION;
                float2 uv : TEXCOORD0;
            };

            struct v2f
            {
                float2 uv : TEXCOORD0;
                float4 vertex : SV_POSITION;
            };

            v2f vert (appdata v)
            {
                v2f o;
                o.vertex = UnityObjectToClipPos(v.vertex);
                o.uv = v.uv;
                return o;
            }

			Texture2D _CameraDepthTexture;
			float4 _CameraDepthTexture_TexelSize;

			Texture2D _GBuffer;
			float4 _GBuffer_TexelSize;

			SamplerState my_point_clamp_sampler;

			float _DepthThreshold = 0.1;
			float _NormalThreshold = 0;
			
			float decodeDepth(float2 uv)
			{
				float gbDepth = _CameraDepthTexture.Sample(my_point_clamp_sampler, uv).x;

				#ifdef _ORTHO_ON
				#if !defined(UNITY_REVERSED_Z)
					gbDepth = 2 * gbDepth - 1;
				#endif
					return -(gbDepth - UNITY_MATRIX_P[2][3]) / UNITY_MATRIX_P[2][2];
				#else
					return DECODE_EYEDEPTH(gbDepth);
				#endif
			}

			bool compDepths(float x, float y, float centerDepth, float2 centerUV)
			{
				float2 _uv = centerUV + float2(x, y) * _GBuffer_TexelSize;
				float depth = decodeDepth(_uv);
				return abs(depth - centerDepth) > _DepthThreshold;
			}

			bool detectDepth(float2 uv)
			{
				bool isDraw = false;
				float centerDepth = decodeDepth(uv);

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
				isDraw = isDraw || compNormals(-1,  0, centerNormal, uv);
				isDraw = isDraw || compNormals(-1,  1, centerNormal, uv);
				isDraw = isDraw || compNormals( 0, -1, centerNormal, uv);
				isDraw = isDraw || compNormals( 0,  1, centerNormal, uv);
				isDraw = isDraw || compNormals( 1, -1, centerNormal, uv);
				isDraw = isDraw || compNormals( 1,  0, centerNormal, uv);
				isDraw = isDraw || compNormals( 1,  1, centerNormal, uv);
				
				return isDraw;
			}

            fixed4 frag (v2f i) : SV_Target
            {
				bool disDraw = detectDepth(i.uv);
				bool nisDraw = detectNormal(i.uv);

				clip((disDraw || nisDraw) - 0.1);
				return float4(0, 0, 0, 1);

				//if (disDraw == true && nisDraw == true) return float4(0, 0, 1, 1);
				//if (disDraw == true && nisDraw == false) return float4(1, 0, 0, 1);
				//if (disDraw == false && nisDraw == true) return float4(0, 1, 0, 1);
				//clip(-1);
				//return float4(0, 0, 0, 0);

				//if (nisDraw == true) return float4(0, 1, 0, 1);
				//float3 n = sampleNormal(i.uv);
				//return float4(n.xyz, 1);

				//if (disDraw == true) return float4(1, 0, 0, 1);
				//float c = decodeDepth(i.uv);
				//c = c * 2 +  0.5;
				//return float4(c, c, c, 1);
            }
            ENDCG
        }
    }
}
