using System;
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

        private (Renderer original, Mesh verticesMesh, ComputeBuffer vertices, ComputeBuffer normals, ComputeBuffer vertexIdxs, Mesh indicesMesh) bakedMesh;

        public void release()
        {
            bakedMesh.vertices?.Release();
            bakedMesh.normals?.Release();
            bakedMesh.vertexIdxs?.Release();
        }

        static void AddLines(HashSet<Tuple<int, int>> lineSet, int[] indices)
        {
            for (int i = 0; i < indices.Length; i += 3)
            {
                int idx0 = indices[i];
                int idx1 = indices[i + 1];
                int idx2 = indices[i + 2];

                if (idx0 < idx1) lineSet.Add(Tuple.Create(idx0, idx1));
                else lineSet.Add(Tuple.Create(idx1, idx0));

                if (idx1 < idx2) lineSet.Add(Tuple.Create(idx1, idx2));
                else lineSet.Add(Tuple.Create(idx2, idx1));

                if (idx2 < idx0) lineSet.Add(Tuple.Create(idx2, idx0));
                else lineSet.Add(Tuple.Create(idx0, idx2));
            }
        }

        HashSet<Tuple<int, int>> createLineSet()
        {
            int subMeshCount = bakedMesh.verticesMesh.subMeshCount;
            var lineSet = new HashSet<Tuple<int, int>>();

            for (int i = 0; i < subMeshCount; i++)
            {
                int[] subMeshIndices = bakedMesh.verticesMesh.GetIndices(i);
                AddLines(lineSet, subMeshIndices);
            }

            return lineSet;
        }

        void createVertexIdx(HashSet<Tuple<int, int>> lineSet)
        {
            var vertexIdx = new int[lineSet.Count * 4];

            int i = 0;
            foreach (var line in lineSet)
            {
                vertexIdx[i++] = line.Item1;
                vertexIdx[i++] = line.Item2;
                vertexIdx[i++] = line.Item1;
                vertexIdx[i++] = line.Item2;
            }

            bakedMesh.vertexIdxs?.Release();
            bakedMesh.vertexIdxs = new ComputeBuffer(vertexIdx.Length, 4);
            bakedMesh.vertexIdxs.SetData(vertexIdx);
        }

        void createIndicesMesh(HashSet<Tuple<int, int>> lineSet)
        {
            int[] indices = new int[lineSet.Count * 4];

            for(int i=0; i<indices.Length; i+=4)
            {
                indices[i] = i;
                indices[i + 1] = i + 3;
                indices[i + 2] = i + 1;
                indices[i + 3] = i + 2;
            }

            if (bakedMesh.indicesMesh == null) bakedMesh.indicesMesh = new Mesh();

            var dst = bakedMesh.indicesMesh;
            var vertices = new Vector3[indices.Length];
            dst.SetVertices(vertices);
            dst.SetIndices(indices, MeshTopology.Lines, 0);
            dst.UploadMeshData(true);
        }

        void initIndices()
        {
            var lineSet = createLineSet();
            createVertexIdx(lineSet);
            createIndicesMesh(lineSet);
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

            if (bakedMesh.original != mesh) initIndices();

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
            commandBuffer.SetGlobalBuffer("_VertexIdx", bakedMesh.vertexIdxs);
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
