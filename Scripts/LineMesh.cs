using System.Collections.Generic;
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

        private (Renderer original, Mesh verticesMesh, ComputeBuffer vertices, ComputeBuffer normals, Mesh indicesMesh) bakedMesh;

        public void release()
        {
            bakedMesh.vertices?.Release();
        }

        void initIndicesMesh()
        {
            if (bakedMesh.indicesMesh == null) bakedMesh.indicesMesh = new Mesh();

            var indicesList = new List<int>();
            var vm = bakedMesh.verticesMesh;
            int subMeshCount = vm.subMeshCount;

            for(int i=0; i<subMeshCount; i++)
            {
                int[] indices = bakedMesh.verticesMesh.GetIndices(i);
                indicesList.AddRange(indices);
            }

            var dst = bakedMesh.indicesMesh;
            dst.SetVertices(vm.vertices);
            dst.SetIndices(indicesList.ToArray(), MeshTopology.Triangles, 0);
            dst.UploadMeshData(true);
        }

        void bakeMesh(CommandBuffer commandBuffer)
        {
            if (mesh == null) return;

            var smr = mesh as SkinnedMeshRenderer;
            if (smr != null)
            {
                if (bakedMesh.verticesMesh == null) bakedMesh.verticesMesh = new Mesh();
                smr.BakeMesh(bakedMesh.verticesMesh);
            }
            else if (bakedMesh.original != mesh)
            {
                bakedMesh.verticesMesh = mesh.GetComponent<MeshFilter>().sharedMesh;
            }

            if (bakedMesh.original != mesh) initIndicesMesh();

            int len = bakedMesh.verticesMesh.vertices.Length;
            if (bakedMesh.vertices == null || bakedMesh.vertices.count != len)
            {
                bakedMesh.vertices?.Release();
                bakedMesh.vertices = new ComputeBuffer(len, 12);
                bakedMesh.vertices.name = mesh.name + "_vertices";

                bakedMesh.normals?.Release();
                bakedMesh.normals = new ComputeBuffer(len, 12);
                bakedMesh.normals.name = mesh.name + "_normals";
            }

            if (smr != null || bakedMesh.original != mesh)
            {
                bakedMesh.vertices.SetData(bakedMesh.verticesMesh.vertices);
                bakedMesh.normals.SetData(bakedMesh.verticesMesh.normals);
                bakedMesh.original = mesh;
            }

            commandBuffer.SetGlobalBuffer("_Vertices", bakedMesh.vertices);
            commandBuffer.SetGlobalBuffer("_Normals", bakedMesh.normals);
        }

        public void renderLine(CommandBuffer commandBuffer, int modelID)
        {
            if (material.GetTag("LineType", false) == "DeferredInking")
            {
                bakeMesh(commandBuffer);
                var id = new Vector2(modelID, meshID);
                commandBuffer.SetGlobalVector("_ID", id);
                commandBuffer.DrawMesh(bakedMesh.indicesMesh, mesh.localToWorldMatrix, material);
            }
            else commandBuffer.DrawRenderer(mesh, material);
        }
    }
}
