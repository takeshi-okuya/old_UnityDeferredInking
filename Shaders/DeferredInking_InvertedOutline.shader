Shader "DeferredInking/InvertedOutline"
{
    Properties
    {
        _Color("Color", Color) = (0, 0, 0, 1)
        _OutlineWidth("Outline Width", FLOAT) = 0.003
    }
    SubShader
    {
        Tags { "RenderType"="Opaque" "LineType"="InvertedOutline" }
        CULL FRONT
        LOD 100

        Pass
        {
            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag

            #include "UnityCG.cginc"

            struct appdata
            {
                float4 vertex : POSITION;
                float3 normal : NORMAL;
            };

            struct v2f
            {
                float4 vertex : SV_POSITION;
            };

            fixed4 _Color;
            float _OutlineWidth;

            Texture2D _CameraDepthTexture;

            v2f vert (appdata v)
            {
                v2f o;
                float3 viewPos = UnityObjectToViewPos(v.vertex);
                float3 translate = v.normal * _OutlineWidth * (-viewPos.z) / unity_CameraProjection[1][1] * 2;
                o.vertex = UnityObjectToClipPos(v.vertex + translate);
                return o;
            }

            fixed4 frag (v2f i) : SV_Target
            {
                int3 xy0 = int3(i.vertex.xy, 0);
                float sub = i.vertex.z - _CameraDepthTexture.Load(xy0).x;

                #ifdef UNITY_REVERSED_Z
                    clip(sub);
                #else
                    clip(-sub);
                #endif
                
                return _Color;
            }
            ENDCG
        }
    }
}
