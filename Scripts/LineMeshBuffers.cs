using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using UnityEngine;
using UnityEngine.Rendering;

namespace WCGL
{
    struct LineMeshBuffers
    {
        Renderer original;
        Mesh verticesMesh;

        ComputeBuffer vertices;
        ComputeBuffer normals;
        Mesh indicesMesh;

        public void release()
        {
            vertices?.Release();
            normals?.Release();
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
            int subMeshCount = verticesMesh.subMeshCount;
            var lineSet = new HashSet<Tuple<int, int>>();

            for (int i = 0; i < subMeshCount; i++)
            {
                int[] subMeshIndices = verticesMesh.GetIndices(i);
                AddLines(lineSet, subMeshIndices);
            }

            return lineSet;
        }

        [StructLayout(LayoutKind.Explicit)]
        public struct IntFloat
        {
            [FieldOffset(0)] public int _int;
            [FieldOffset(0)] public float _float;
        }

        Vector3[] createVertex(HashSet<Tuple<int, int>> lineSet)
        {
            var vertexIdx = new Vector3[lineSet.Count * 4];

            int i = 0;
            IntFloat idx1, idx2;
            idx1._float = idx2._float = 0; //for compile.
            foreach (var line in lineSet)
            {
                idx1._int = line.Item1;
                idx2._int = line.Item2;

                vertexIdx[i++] = new Vector3(idx1._float, idx2._float, -1);
                vertexIdx[i++] = new Vector3(idx2._float, idx1._float, -1);
                vertexIdx[i++] = new Vector3(idx1._float, idx2._float, 1);
                vertexIdx[i++] = new Vector3(idx2._float, idx1._float, 1);
            }

            return vertexIdx;
        }

        int[] createIndicesMesh(HashSet<Tuple<int, int>> lineSet)
        {
            int[] indices = new int[lineSet.Count * 4];

            for (int i = 0; i < indices.Length; i += 4)
            {
                indices[i] = i;
                indices[i + 1] = i + 3;
                indices[i + 2] = i + 1;
                indices[i + 3] = i + 2;
            }

            return indices;
        }

        void initIndices()
        {
            var lineSet = createLineSet();
            var vertices = createVertex(lineSet);
            var indices = createIndicesMesh(lineSet);

            if (indicesMesh == null) indicesMesh = new Mesh();

            indicesMesh.SetVertices(vertices);
            indicesMesh.SetIndices(indices, MeshTopology.Quads, 0);
            indicesMesh.UploadMeshData(true);
        }

        void bakeMesh(Renderer mesh)
        {
            if (mesh == null) return;

            var smr = mesh as SkinnedMeshRenderer;
            if (smr != null)
            {
                if (verticesMesh == null) verticesMesh = new Mesh();
                smr.BakeMesh(verticesMesh);
            }
            else if (original != mesh)
            {
                verticesMesh = mesh.GetComponent<MeshFilter>().sharedMesh;
            }

            if (original != mesh) initIndices();

            int len = verticesMesh.vertices.Length;
            if (vertices == null || vertices.count != len)
            {
                vertices?.Release();
                vertices = new ComputeBuffer(len, 12);
                vertices.name = mesh.name + "_vertices";

                normals?.Release();
                normals = new ComputeBuffer(len, 12);
                normals.name = mesh.name + "_normals";
            }

            if (smr != null || original != mesh)
            {
                vertices.SetData(verticesMesh.vertices);
                normals.SetData(verticesMesh.normals);
                original = mesh;
            }
        }

        public void render(CommandBuffer commandBuffer, Renderer renderer, Material material)
        {
            bakeMesh(renderer);
            commandBuffer.SetGlobalBuffer("_Vertices", vertices);
            commandBuffer.SetGlobalBuffer("_Normals", normals);
            commandBuffer.DrawMesh(indicesMesh, renderer.localToWorldMatrix, material);
        }
    }
}
