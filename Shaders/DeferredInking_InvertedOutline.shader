Shader "DeferredInking/InvertedOutline"
{
    Properties
    {
        _Color("Color", Color) = (0, 0, 0, 1)
        [Header(Outline Width)]
        _OutlineWidth("Outline Width", FLOAT) = 0.002
        [Toggle] _Width_By_Distance("Width by Distance", Float) = 0
        [Toggle] _Width_By_FoV("Width by FoV", Float) = 0
        _MinWidth("Min Width", FLOAT) = 0.5
        _MaxWidth("Max Width", FLOAT) = 4.0
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

            #pragma multi_compile _ _WIDTH_BY_DISTANCE_ON
            #pragma multi_compile _ _WIDTH_BY_FOV_ON
            #pragma multi_compile _ _ORTHO_ON

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
            float _Width_By_Distance;
            float _Width_By_FoV;
            float _MinWidth;
            float _MaxWidth;

            Texture2D _CameraDepthTexture;

            float compWidth(float distance)
            {
                float width = _OutlineWidth;

                if (unity_OrthoParams.w == 0.f && _Width_By_Distance == 0.f) {
                    width *= distance;
                } else if (unity_OrthoParams.w && _Width_By_Distance) {
                    width /= distance;
                }

                float fovScale = lerp(unity_CameraProjection[1][1], 4.167, _Width_By_FoV); //4.167: cot(27deg/2). 27deg: 50mm 
                width /= fovScale;

                if (_Width_By_Distance || _Width_By_Distance) {
                    float scale = lerp(distance, 1.0f, unity_OrthoParams.w);
                    scale /= unity_CameraProjection[1][1];
                    width = clamp(width, _MinWidth * scale, _MaxWidth * scale);
                }

                return width * 2.0 * 0.001f;
            }

            v2f vert (appdata v)
            {
                v2f o;
                float viewPosZ = -UnityObjectToViewPos(v.vertex).z;
                float width = compWidth(viewPosZ);
                float3 translate = v.normal * width;
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
