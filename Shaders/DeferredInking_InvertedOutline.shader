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

		[Space]
		[Toggle] _Use_Curvature("Use Curvature", Float) = 0
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
			#include "Curvature.cginc"

            #pragma multi_compile _ _WIDTH_BY_DISTANCE_ON
            #pragma multi_compile _ _WIDTH_BY_FOV_ON
			#pragma multi_compile _ _USE_CURVATURE_ON
			#pragma multi_compile _ _ORTHO_ON

            struct appdata
            {
                float4 vertex : POSITION;
                float3 normal : NORMAL;
				uint id : SV_VertexID;
            };

            struct v2f
            {
                float4 vertex : SV_POSITION;
            };

            fixed4 _Color;
            float _OutlineWidth;
            float _MinWidth;
            float _MaxWidth;

            Texture2D _CameraDepthTexture;

            float compWidth(float distance)
            {
                float width = _OutlineWidth;

                #if !defined(_ORTHO_ON) && !defined(_WIDTH_BY_DISTANCE_ON)
                    width *= distance;
                #elif defined(_ORTHO_ON) && defined(_WIDTH_BY_DISTANCE_ON)
                    width /= distance;
                #endif

                #ifdef _WIDTH_BY_FOV_ON
                    width /= 4.167;
                #else
                    width /= unity_CameraProjection[1][1];
                #endif

                #if defined(_WIDTH_BY_DISTANCE_ON) || defined(_WIDTH_BY_FOV_ON)
                    #ifdef _ORTHO_ON
                        float scale = 1.0f / unity_CameraProjection[1][1];
                    #else
                        float scale = distance / unity_CameraProjection[1][1];
                    #endif
                    width = clamp(width, _MinWidth * scale, _MaxWidth * scale);
                #endif

                return width * 2.0 * 0.001f;
            }

            v2f vert (appdata v)
            {
                v2f o;
                float viewPosZ = -UnityObjectToViewPos(v.vertex).z;
                float width = compWidth(viewPosZ) * compCurvatureWidth(v.id);
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
