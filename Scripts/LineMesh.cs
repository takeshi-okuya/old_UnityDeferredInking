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

        private (Renderer original, Mesh mesh, ComputeBuffer vertices) bakedMesh;

        ~LineMesh()
        {
            bakedMesh.vertices?.Release();
        }

        void bakeMesh(CommandBuffer commandBuffer)
        {
            if (mesh == null) return;

            var smr = mesh as SkinnedMeshRenderer;
            if (smr != null)
            {
                if (bakedMesh.mesh == null) bakedMesh.mesh = new Mesh();
                smr.BakeMesh(bakedMesh.mesh);
            }
            else if (bakedMesh.original != mesh)
            {
                bakedMesh.mesh = mesh.GetComponent<MeshFilter>().sharedMesh;
            }

            int len = bakedMesh.mesh.vertices.Length;
            if (bakedMesh.vertices == null || bakedMesh.vertices.count != len)
            {
                bakedMesh.vertices?.Release();
                bakedMesh.vertices = new ComputeBuffer(len, 12);
                bakedMesh.vertices.name = mesh.name;
            }

            if (smr != null || bakedMesh.original != mesh)
            {
                bakedMesh.vertices.SetData(bakedMesh.mesh.vertices);
                bakedMesh.original = mesh;
            }

            commandBuffer.SetGlobalBuffer("_Vertices", bakedMesh.vertices);

            var rb = smr?.rootBone;
            if (rb == null) commandBuffer.SetGlobalMatrix("_RootBone", Matrix4x4.identity);
            else
            {
                var mat = rb.transform.worldToLocalMatrix * mesh.transform.localToWorldMatrix;
                commandBuffer.SetGlobalMatrix("_RootBone", mat);
            }
        }

        public void renderLine(CommandBuffer commandBuffer, int modelID)
        {
            if (material.GetTag("LineType", false) == "DeferredInking")
            {
                bakeMesh(commandBuffer);
                var id = new Vector2(modelID, meshID);
                commandBuffer.SetGlobalVector("_ID", id);
            }

            commandBuffer.DrawRenderer(mesh, material);
        }
    }
}
