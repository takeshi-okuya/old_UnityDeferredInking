Shader "DeferredInking/Line"
{
    Properties
    {
        _Color("Color", Color) = (0, 0, 0, 1)
        _OutlineWidth("Outline Width", FLOAT) = 0.003
        _DepthThreshold("Threshold_Depth", FLOAT) = 2.0
        _DepthBias("Depth_Bias", FLOAT) = 0.005
    }
    SubShader
    {
        Tags { "RenderType"="Opaque" }
        LOD 100

        Pass
        {
            ZTest Always

            CGPROGRAM
            #pragma vertex vert
            #pragma geometry geom
            #pragma fragment frag

            #include "UnityCG.cginc"

            struct appdata
            {
                float4 vertex : POSITION;
            };

            struct v2g
            {
                float4 vertex : SV_POSITION;
                float2 projXY : POSITION1;
            };

            struct g2f
            {
                float4 vertex : SV_POSITION;
                float4 center : POSITION1;
            };

            fixed4 _Color;
            float _OutlineWidth;
            float _DepthThreshold;
            float _DepthBias;

            Texture2D _GBuffer;
            float4 _GBuffer_TexelSize;
            SamplerState my_point_clamp_sampler;

            uint meshID;

            Texture2D _CameraDepthTexture;
            float4 _CameraDepthTexture_TexelSize;
            SamplerState my_linear_clamp_sampler;

            v2g vert (appdata v)
            {
                v2g o;
                o.vertex = UnityObjectToClipPos(v.vertex);
                o.projXY = o.vertex.xy / o.vertex.w;

                return o;
            }

            void appendPoint(v2g p, float2 translate, float2 right, inout g2f o, inout TriangleStream<g2f> ts)
            {
                float2 xy = (p.projXY + translate) * p.vertex.w;
                o.vertex = float4(xy, p.vertex.zw);
                o.center = p.vertex;
                
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

                appendPoint(p1, -translate, right, o, ts);
                appendPoint(p2, -translate, right, o, ts);
                appendPoint(p1, translate, right, o, ts);
                appendPoint(p2, translate, right, o, ts);
                ts.RestartStrip();
            }

            [maxvertexcount(12)]
            void geom(triangle v2g input[3], uint pid : SV_PrimitiveID, inout TriangleStream<g2f> ts)
            {
                float3 v01 = float3(input[1].projXY - input[0].projXY, 0);
                float3 v02 = float3(input[2].projXY - input[0].projXY, 0);

                if (cross(v01, v02).z <= 0) return;

                float aspect = (-UNITY_MATRIX_P[1][1]) / UNITY_MATRIX_P[0][0];

                generateLine(input[0], input[1], aspect, ts);
                generateLine(input[1], input[2], aspect, ts);
                generateLine(input[2], input[0], aspect, ts);
            }

            float sampleDepth(float2 uv)
            {
                float4 cameraDepth = _CameraDepthTexture.Sample(my_linear_clamp_sampler, uv);
                return DECODE_EYEDEPTH(cameraDepth.xy).x;
            }

            float3x3 sampleDepth3x3(float2 uv)
            {
                float3x3 o;

                o[0].x = sampleDepth(uv - _CameraDepthTexture_TexelSize.xy);
                o[0].y = sampleDepth(uv + float2(0, -_CameraDepthTexture_TexelSize.y));
                o[0].z = sampleDepth(uv + float2(_CameraDepthTexture_TexelSize.x, -_CameraDepthTexture_TexelSize.y));

                o[1].x = sampleDepth(uv + float2(-_CameraDepthTexture_TexelSize.x, 0));
                //o[1].y = sampleDepth(uv);
                o[1].z = sampleDepth(uv + float2(_CameraDepthTexture_TexelSize.x, 0));

                o[2].x = sampleDepth(uv + float2(-_CameraDepthTexture_TexelSize.x, _CameraDepthTexture_TexelSize.y));
                o[2].y = sampleDepth(uv + float2(0, _CameraDepthTexture_TexelSize.y));
                o[2].z = sampleDepth(uv + _CameraDepthTexture_TexelSize.xy);

                return o;
            }

            float depthSobel(float2 uv)
            {
                float3x3 d = sampleDepth3x3(uv);

                float2 sumsX = float2(1, -1) * d[0].xz + float2(2, -2) * d[1].xz + float2(1, -1) * d[2].xz;
                float lx = sumsX.x + sumsX.y;

                float3 sumsY = float3(1, 2, 1) * d[0] + float3(-1, -2, -1) * d[2];
                float ly = sumsY.x + sumsY.y + sumsY.z;

                return sqrt(lx * lx + ly * ly);
            }

            float id(float2 uv)
            {
                float sum = 0;
                for (int y = -1; y <= 1; y++)
                {
                    for (int x = -1; x <= 1; x++)
                    {
                        float2 _uv = uv + float2(x, y) * _GBuffer_TexelSize;
                        float4 g = _GBuffer.Sample(my_point_clamp_sampler, _uv);
                        float GBufferID = g.g * 255.0f;
                        sum += abs(GBufferID - meshID);
                    }
                }

                return sum - 0.1;
            }

            fixed4 frag (g2f i) : SV_Target
            {
                float2 uv = (i.center.xy / i.center.w + 1.0f) * 0.5f;
                uv.y = 1 - uv.y;

                float cameraDepth = DECODE_EYEDEPTH(_CameraDepthTexture.Sample(my_point_clamp_sampler, uv)).x;
                clip(cameraDepth - i.center.w + _DepthBias);

                clip(id(uv));

                //float edge = depthSobel(i.center);
                //clip(edge - _DepthThreshold);

                return _Color;
            }
            ENDCG
        }
    }

    FallBack "Diffuse"
}
