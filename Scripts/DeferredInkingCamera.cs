using System.Collections;
using System.Collections.Generic;
using UnityEngine;
using UnityEngine.Rendering;

namespace WCGL
{
    [ExecuteInEditMode]
    public class DeferredInkingCamera : MonoBehaviour
    {
        static Material DrawMaterial;

        Camera cam;
        CommandBuffer commandBuffer;
        RenderTexture lineBuffer;

        void Start() { } //for Inspector ON_OFF

        void initRenderTexture()
        {
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
            }
        }

        private void OnPreRender()
        {
            if (lineBuffer.width != cam.pixelWidth || lineBuffer.height != cam.pixelHeight)
            {
                lineBuffer.Release();
                initRenderTexture();
            }

            commandBuffer.SetRenderTarget(lineBuffer);
            commandBuffer.ClearRenderTarget(true, true, Color.clear);

            foreach(var model in DeferredInkingModel.Instances)
            {
                if (model.isActiveAndEnabled == false) continue;

                var lineMat = model.material;
                if (lineMat == null) continue;

                foreach(var mesh in model.meshes)
                {
                    if (mesh == null || mesh.enabled == false) continue;
                    commandBuffer.DrawRenderer(mesh, lineMat);
                }
            }

            commandBuffer.Blit(lineBuffer, BuiltinRenderTextureType.CameraTarget, DrawMaterial);
        }

        private void OnPostRender()
        {
            commandBuffer.Clear();
        }
    }
}