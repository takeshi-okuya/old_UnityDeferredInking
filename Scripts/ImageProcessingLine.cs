using System;
using System.Collections;
using System.Collections.Generic;
using UnityEngine;
using UnityEngine.Rendering;

namespace WCGL
{
    [ExecuteInEditMode]
    public class ImageProcessingLine : MonoBehaviour
    {
        static Material DrawMaterial, GBufferMaterial;

        Camera cam;
        CommandBuffer commandBuffer;
        RenderTexture gBuffer;

        [SerializeField, Range(-1, 1)]
        float normalThreshold = 0;
        public float depthThreshold = 0.1f;

        void Start() { } //for Inspector ON_OFF

        void resizeRenderTexture()
        {
            var gbSize = new Vector2Int(cam.pixelWidth, cam.pixelHeight);

            if (gBuffer == null || gBuffer.width != gbSize.x || gBuffer.height != gbSize.y)
            {
                if (gBuffer != null) gBuffer.Release();
                gBuffer = new RenderTexture(gbSize.x, gbSize.y, 0, RenderTextureFormat.ARGB32);
                gBuffer.name = "DeferredInking_G-Buffer";
                gBuffer.wrapMode = TextureWrapMode.Clamp;
                gBuffer.filterMode = FilterMode.Point;
            }
        }

        void Awake()
        {
            cam = GetComponent<Camera>();
            if (cam == null)
            {
                Debug.LogError(name + " does not have camera.");
                return;
            }

            commandBuffer = new CommandBuffer();
            commandBuffer.name = "DeferredInking";
            cam.AddCommandBuffer(CameraEvent.AfterSkybox, commandBuffer);

            resizeRenderTexture();

            if (DrawMaterial == null)
            {
                var shader = Shader.Find("Hidden/ImageProcessingLine");
                DrawMaterial = new Material(shader);

                shader = Shader.Find("Hidden/DeferredInking/GBuffer");
                GBufferMaterial = new Material(shader);
            }
        }

        private void OnPreRender()
        {
            resizeRenderTexture();

            var depthBuffer = (RenderTargetIdentifier)BuiltinRenderTextureType.Depth;

            commandBuffer.SetRenderTarget(gBuffer.colorBuffer, depthBuffer);
            commandBuffer.ClearRenderTarget(false, true, Color.clear);
            render(gBuffer);

            if (cam.orthographic) { DrawMaterial.EnableKeyword("_ORTHO_ON"); }
            else { DrawMaterial.DisableKeyword("_ORTHO_ON"); }
            DrawMaterial.SetFloat("_NormalThreshold", normalThreshold);
            DrawMaterial.SetFloat("_DepthThreshold", depthThreshold);
            commandBuffer.SetGlobalTexture("_GBuffer", gBuffer.colorBuffer);
            commandBuffer.Blit(null, BuiltinRenderTextureType.CameraTarget, DrawMaterial);
        }

        private void render(RenderTexture target)
        {
            foreach (var model in DeferredInkingModel.Instances)
            {
                if (model.isActiveAndEnabled == false) continue;
                var id = new Vector2(model.modelID, 0);

                foreach (var mesh in model.meshes)
                {
                    var renderer = mesh.mesh;
                    if (renderer == null || renderer.enabled == false) continue;

                    id.y = mesh.meshID;
                    commandBuffer.SetGlobalVector("_ID", id);
                    commandBuffer.DrawRenderer(renderer, GBufferMaterial);
                }
            }
        }

        private void OnPostRender()
        {
            commandBuffer.Clear();
        }
    }
}