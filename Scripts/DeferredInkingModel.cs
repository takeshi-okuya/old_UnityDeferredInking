using System.Collections;
using System.Collections.Generic;
using UnityEngine;
using UnityEngine.Rendering;

namespace WCGL
{
    [ExecuteInEditMode]
    public class DeferredInkingModel : MonoBehaviour
    {
        [System.Serializable]
        public class Mesh
        {
            public Renderer mesh;
            public Material material;
            [Range(0, 255)] public int meshID;

            public void render(CommandBuffer commandBuffer, DeferredInkingCamera.RenderPhase phase, int modelID, Material GBufferMaterial)
            {
                var renderer = mesh;
                if (renderer == null || renderer.enabled == false) return;

                Material mat;
                if (phase == DeferredInkingCamera.RenderPhase.Line)
                {
                    mat = material;
                    if (material == null) return;
                }
                else
                {
                    mat = GBufferMaterial;
                }

                if (phase == DeferredInkingCamera.RenderPhase.GBuffer || material.GetTag("LineType", false) == "DeferredInking")
                {
                    var id = new Vector2(modelID, meshID);
                    commandBuffer.SetGlobalVector("_ID", id);
                }
                commandBuffer.DrawRenderer(renderer, mat);
            }
        }

        readonly static List<DeferredInkingModel> Instances = new List<DeferredInkingModel>();
        public static IReadOnlyList<DeferredInkingModel> GetInstances() { return Instances; }

        [Range(1, 255)] public int modelID = 255;
        public List<Mesh> meshes = new List<Mesh>();

        void OnEnable()
        {
            Instances.Add(this);
        }

        void OnDisable()
        {
            Instances.Remove(this);
        }

        public void render(CommandBuffer commandBuffer, DeferredInkingCamera.RenderPhase phase, Material GBufferMaterial)
        {
            foreach (var mesh in meshes)
            {
                mesh.render(commandBuffer, phase, modelID, GBufferMaterial);
            }
        }
    }
}
