using UnityEngine;
using UnityEngine.Rendering;

namespace WCGL
{
    [System.Serializable]
    public class LineMesh
    {
        public Renderer mesh;
        public Material material;
        [Range(0, 255)] public int meshID;

        private LineMeshBuffers buffers;

        public void release()
        {
            buffers.release();
        }

        public void renderLine(CommandBuffer commandBuffer, int modelID)
        {
            if (material.GetTag("LineType", false) == "DeferredInking")
            {
                var id = new Vector2(modelID, meshID);
                commandBuffer.SetGlobalVector("_ID", id);
                buffers.render(commandBuffer, mesh, material);
            }
            else commandBuffer.DrawRenderer(mesh, material);
        }
    }
}
