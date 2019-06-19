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

        [Range(0.1f, 3.0f)]
        public float sigma = 1.0f;
        Vector4[] filter = new Vector4[3];

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

        void renewFilter()
        {
            float sum = 0;
            for (int y = -1; y <= 1; y++)
            {
                for (int x = -1; x <= 1; x++)
                {
                    float entry = Mathf.Exp(-(x * x + y * y) / (2 * sigma * sigma));
                    sum += entry;
                    filter[y + 1][x + 1] = entry;
                }
            }

            for(int i=0; i<3; i++)
            {
                filter[i] /= sum;
            }
        }
        private void OnPreRender()
        {
            if (lineBuffer == null || lineBuffer.width != cam.pixelWidth || lineBuffer.height != cam.pixelHeight)
            {
                initRenderTexture();
            }

            commandBuffer.SetRenderTarget(gBuffer, BuiltinRenderTextureType.Depth);
            commandBuffer.ClearRenderTarget(false, true, Color.clear);
            render(gBuffer, model => GBufferMaterial);

            commandBuffer.SetRenderTarget(lineBuffer);
            commandBuffer.ClearRenderTarget(true, true, Color.clear);
            commandBuffer.SetGlobalTexture("_GBuffer", gBuffer);
            render(lineBuffer, model => model.material);

            renewFilter();
            commandBuffer.SetGlobalVectorArray("Filter", filter);
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