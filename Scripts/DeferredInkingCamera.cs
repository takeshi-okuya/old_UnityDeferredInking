using System;
using System.Collections;
using System.Collections.Generic;
using UnityEngine;
using UnityEngine.Rendering;

namespace WCGL
{
    [ExecuteInEditMode]
    public class DeferredInkingCamera : MonoBehaviour
    {
        static Material DrawMaterial, GBufferMaterial;

        Camera cam;
        CommandBuffer commandBuffer;
        RenderTexture gBuffer, lineBuffer;

        void Start() { } //for Inspector ON_OFF

        void initRenderTexture()
        {
            if (gBuffer != null) gBuffer.Release();
            gBuffer = new RenderTexture(cam.pixelWidth, cam.pixelHeight, 16);
            gBuffer.name = "DeferredInking_G-Buffer";

            if (lineBuffer != null) lineBuffer.Release();
            lineBuffer = new RenderTexture(cam.pixelWidth, cam.pixelHeight, 16);
            lineBuffer.name = "DeferredInking_line";
            lineBuffer.antiAliasing = 4;
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

            initRenderTexture();

            if (DrawMaterial == null)
            {
                var shader = Shader.Find("Hidden/DeferredInking/Draw");
                DrawMaterial = new Material(shader);

                shader = Shader.Find("Hidden/DeferredInking/gBuffer");
                GBufferMaterial = new Material(shader);
            }
        }

        private void OnPreRender()
        {
            if (lineBuffer == null || lineBuffer.width != cam.pixelWidth || lineBuffer.height != cam.pixelHeight)
            {
                initRenderTexture();
            }

            //commandBuffer.Blit(RenderTexture.active.depthBuffer, gBuffer.depthBuffer);

            var depth = new RenderTargetIdentifier(BuiltinRenderTextureType.Depth);
            commandBuffer.SetRenderTarget(gBuffer, depth);
            commandBuffer.ClearRenderTarget(false, true, Color.clear);
            render(gBuffer, model => GBufferMaterial);

            commandBuffer.SetRenderTarget(lineBuffer);
            commandBuffer.ClearRenderTarget(true, true, Color.clear);
            commandBuffer.SetGlobalTexture("_GBuffer", gBuffer);
            render(lineBuffer, model => model.material);
            commandBuffer.Blit(lineBuffer, BuiltinRenderTextureType.CameraTarget, DrawMaterial);
        }

        private void render(RenderTexture target, Func<DeferredInkingModel, Material> matFunc)
        {
            foreach(var model in DeferredInkingModel.Instances)
            {
                if (model.isActiveAndEnabled == false) continue;

                var mat = matFunc(model);
                if (mat == null) continue;

                commandBuffer.SetGlobalFloat("modelID", model.modelID);

                foreach (var mesh in model.meshes)
                {
                    var renderer = mesh.mesh;
                    if (renderer == null || renderer.enabled == false) continue;

                    commandBuffer.SetGlobalFloat("meshID", mesh.meshID);
                    commandBuffer.DrawRenderer(renderer, mat);
                }
            }
        }

        private void OnPostRender()
        {
            commandBuffer.Clear();
        }
    }
}