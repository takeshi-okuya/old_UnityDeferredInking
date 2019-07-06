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
        RenderTexture gBuffer, gBufferDepth, lineBuffer;

        [Range(0.1f, 3.0f)]
        public float sigma = 1.0f;
        Vector4[] filter = new Vector4[3];

        public enum ResolutionMode { Same, X2, X3, Custom }
        public ResolutionMode gBufferResolutionMode = ResolutionMode.Same;
        public Vector2Int customGBufferResolution = new Vector2Int(1920, 1080);

        enum RenderPhase { GBuffer, Line }

        void Start() { } //for Inspector ON_OFF

        void resizeRenderTexture()
        {
            var camSize = new Vector2Int(cam.pixelWidth, cam.pixelHeight);
            Vector2Int gbSize;

            if (gBufferResolutionMode == ResolutionMode.Same) { gbSize = camSize; }
            else if (gBufferResolutionMode == ResolutionMode.X2) { gbSize = camSize * 2; }
            else if (gBufferResolutionMode == ResolutionMode.X2) { gbSize = camSize * 3; }
            else { gbSize = customGBufferResolution; }

            if (gBuffer == null || gBuffer.width != gbSize.x || gBuffer.height != gbSize.y)
            {
                if (gBuffer != null) gBuffer.Release();
                gBuffer = new RenderTexture(gbSize.x, gbSize.y, 0, RenderTextureFormat.ARGB32);
                gBuffer.name = "DeferredInking_G-Buffer";
                gBuffer.wrapMode = TextureWrapMode.Clamp;
                gBuffer.filterMode = FilterMode.Point;
            }

            if (gBufferResolutionMode != ResolutionMode.Same &&
                (gBufferDepth == null || gBufferDepth.width != gbSize.x || gBufferDepth.height != gbSize.y))
            {
                if (gBufferDepth != null) gBufferDepth.Release();
                gBufferDepth = new RenderTexture(gbSize.x, gbSize.y, 16, RenderTextureFormat.Depth);
                gBufferDepth.name = "DeferredInking_G-BufferDepth";
                gBufferDepth.wrapMode = TextureWrapMode.Clamp;
                gBufferDepth.filterMode = FilterMode.Point;
            }

            if (lineBuffer == null || lineBuffer.width != cam.pixelWidth || lineBuffer.height != cam.pixelHeight)
            {
                if (lineBuffer != null) lineBuffer.Release();
                lineBuffer = new RenderTexture(cam.pixelWidth, cam.pixelHeight, 16);
                lineBuffer.name = "DeferredInking_line";
                lineBuffer.antiAliasing = 4;
                lineBuffer.wrapMode = TextureWrapMode.Clamp;
                lineBuffer.filterMode = FilterMode.Point;
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

            for (int i = 0; i < 3; i++)
            {
                filter[i] /= sum;
            }
        }

        private void OnPreRender()
        {
            resizeRenderTexture();

            var depthBuffer = (gBufferResolutionMode == ResolutionMode.Same) ?
                (RenderTargetIdentifier)BuiltinRenderTextureType.Depth : gBufferDepth;
            if (depthBuffer == gBufferDepth) renderGBufferZero();

            commandBuffer.SetRenderTarget(gBuffer.colorBuffer, depthBuffer);
            commandBuffer.ClearRenderTarget(false, true, Color.clear);
            render(gBuffer, RenderPhase.GBuffer);

            commandBuffer.SetRenderTarget(lineBuffer);
            commandBuffer.ClearRenderTarget(true, true, Color.clear);
            commandBuffer.SetGlobalTexture("_GBuffer", gBuffer.colorBuffer);
            commandBuffer.SetGlobalTexture("_GBufferDepth", depthBuffer);
            render(lineBuffer, RenderPhase.Line);

            renewFilter();
            commandBuffer.SetGlobalVectorArray("Filter", filter);
            commandBuffer.Blit(lineBuffer, BuiltinRenderTextureType.CameraTarget, DrawMaterial);
        }

        private void addShadowCaster(Renderer r, Material mat, int meshIdx)
        {
            int passCount = mat.passCount;

            for (int i = 0; i < passCount; i++)
            {
                if (mat.GetPassName(i) == "ShadowCaster")
                {
                    commandBuffer.DrawRenderer(r, mat, meshIdx, i);
                    return;
                }
            }
        }

        private void renderGBufferZero()
        {
            commandBuffer.SetRenderTarget(gBuffer, gBufferDepth);
            commandBuffer.ClearRenderTarget(true, true, Color.clear);
            commandBuffer.SetGlobalVector("unity_LightShadowBias", Vector4.zero);

            var renderers = FindObjectsOfType<Renderer>();
            foreach (var r in renderers)
            {
                if (r.isVisible == false) continue;
                var sr = r as SkinnedMeshRenderer;

                var mesh = sr == null ? r.GetComponent<MeshFilter>().sharedMesh : sr.sharedMesh;
                int subMeshCount = mesh.subMeshCount;
                var materials = r.sharedMaterials;

                for (int i = 0; i < subMeshCount; i++)
                {
                    int matIdx = Math.Min(i, materials.Length - 1);
                    var mat = materials[matIdx];
                    addShadowCaster(r, mat, i);
                }
            }
        }

        private void render(RenderTexture target, RenderPhase phase)
        {
            Material mat = GBufferMaterial;

            foreach (var model in DeferredInkingModel.Instances)
            {
                if (model.isActiveAndEnabled == false) continue;
                commandBuffer.SetGlobalFloat("modelID", model.modelID);

                foreach (var mesh in model.meshes)
                {
                    var renderer = mesh.mesh;
                    if (renderer == null || renderer.enabled == false) continue;

                    if (phase == RenderPhase.GBuffer)
                    {
                        commandBuffer.SetGlobalInt("_Cull", (int)mesh.gBufferCulling);
                    }
                    else //RenderPhase.Line
                    {
                        mat = mesh.material;
                        if (mat == null) continue;
                    }
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