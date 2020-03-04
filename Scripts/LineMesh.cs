﻿using UnityEngine;
using UnityEngine.Rendering;

namespace WCGL
{
    [System.Serializable]
    public class LineMesh
    {
        public Renderer mesh;
        public Material material;
        [Range(0, 255)] public int meshID;

        private (Renderer original, Mesh verticesMesh, ComputeBuffer vertices) bakedMesh;

        public void release()
        {
            bakedMesh.vertices?.Release();
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

            int len = bakedMesh.verticesMesh.vertices.Length;
            if (bakedMesh.vertices == null || bakedMesh.vertices.count != len)
            {
                bakedMesh.vertices?.Release();
                bakedMesh.vertices = new ComputeBuffer(len, 12);
                bakedMesh.vertices.name = mesh.name;
            }

            if (smr != null || bakedMesh.original != mesh)
            {
                bakedMesh.vertices.SetData(bakedMesh.verticesMesh.vertices);
                bakedMesh.original = mesh;
            }

            commandBuffer.SetGlobalBuffer("_Vertices", bakedMesh.vertices);

            var rb = smr?.rootBone;
            var rootBoneMatrix = (rb == null) ? Matrix4x4.identity : rb.transform.worldToLocalMatrix * mesh.transform.localToWorldMatrix;
            commandBuffer.SetGlobalMatrix("_RootBone", rootBoneMatrix);
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
