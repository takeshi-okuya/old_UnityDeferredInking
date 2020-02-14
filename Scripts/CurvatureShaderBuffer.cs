using UnityEngine;
using System.Runtime.InteropServices;
using System;
using System.Linq;
using System.Collections.Generic;
using UnityEngine.Rendering;

namespace WCGL
{
    public class CurvatureShaderBuffer
    {
        struct Line { public int v1, v2; };
        struct Neighbor { public int v1, v2, v3; };
        [StructLayout(LayoutKind.Sequential, Pack = 1)]
        struct NeighborLoop { public Int32 startIdx, count; }


        private ComputeBuffer cbNeighborLoops;
        private ComputeBuffer cbNeighborIdxs;
        private ComputeBuffer cbVertices;

        public CurvatureShaderBuffer(Mesh mesh)
        {
            Debug.Log(mesh.name);

            var neighborLists = generateNeighborLists(mesh);
            var neighborLoops = generateNeighborLoops(neighborLists);
            var neighborIdxs = generateNeighborIdxs(neighborLists);

            int size = Marshal.SizeOf(typeof(NeighborLoop));
            if (size != 8) throw new Exception();
            cbNeighborLoops = new ComputeBuffer(mesh.vertexCount, size);
            cbNeighborLoops.SetData(neighborLoops);

            size = Marshal.SizeOf(typeof(int));
            if (size != 4) throw new Exception();
            cbNeighborIdxs = new ComputeBuffer(neighborIdxs.Length, size);
            cbNeighborIdxs.SetData(neighborIdxs);

            cbVertices = new ComputeBuffer(mesh.vertexCount, 12);
            cbVertices.SetData(mesh.vertices);
        }

        public void generateCommendBuffer(CommandBuffer commandBuffer)
        {
            commandBuffer.SetGlobalBuffer("NeighborLoops", cbNeighborLoops);
            commandBuffer.SetGlobalBuffer("NeighborIdxs", cbNeighborIdxs);
            commandBuffer.SetGlobalBuffer("Vertices", cbVertices);
            //     m.SetInt("EnableCurvature", 1);
        }


        static int[] generateOverlapIds(Vector3[] vertices)
        {
            int[] dst = new int[vertices.LongLength];

            for (int i = 0; i < vertices.Length; i++)
            {
                var v = vertices[i];
                for (int j = 0; j < vertices.Length; j++)
                {
                    if (vertices[j] == v)
                    {
                        dst[i] = j;
                        break;
                    }
                }
            }

            return dst;
        }

        static Line[][] generateLineLists(Mesh mesh, int[] overlapIds)
        {
            List<Line>[] lineLists = new List<Line>[mesh.vertexCount];
            for (int i = 0; i < lineLists.Length; i++)
            {
                lineLists[i] = new List<Line>();
            }

            int[] triangles = mesh.triangles;
            for (int i = 0; i < triangles.Length; i += 3)
            {
                int id0 = overlapIds[triangles[i]];
                int id1 = overlapIds[triangles[i + 1]];
                int id2 = overlapIds[triangles[i + 2]];

                Line l;

                l.v1 = id1;
                l.v2 = id2;
                lineLists[id0].Add(l);

                l.v1 = id2;
                l.v2 = id0;
                lineLists[id1].Add(l);

                l.v1 = id0;
                l.v2 = id1;
                lineLists[id2].Add(l);
            }

            return lineLists.Select(x => x.ToArray()).ToArray();
        }

        static Neighbor[] lineListToNeighborList(Line[] lineList)
        {
            var neighborList = new List<Neighbor>();

            for (int i = 0; i < lineList.Length; i++)
            {
                Neighbor n;
                n.v1 = lineList[i].v1;
                for (int j = 0; j < lineList.Length; j++)
                {
                    if (n.v1 == lineList[j].v2)
                    {
                        n.v2 = lineList[i].v2;
                        n.v3 = lineList[j].v1;
                        neighborList.Add(n);
                        break;
                    }
                }
            }

            return neighborList.ToArray();
        }

        static Neighbor[][] generateNeighborLists(Mesh mesh)
        {
            int[] overlapIds = generateOverlapIds(mesh.vertices);
            var lineLists = generateLineLists(mesh, overlapIds);

            var neighbors = new Neighbor[mesh.vertexCount][];
            for (int i = 0; i < neighbors.Length; i++)
            {
                int id = overlapIds[i];
                if (i == id) neighbors[i] = lineListToNeighborList(lineLists[i]);
                else neighbors[i] = neighbors[id];
            }

            return neighbors;
        }

        static NeighborLoop[] generateNeighborLoops(Neighbor[][] neighborLists)
        {
            var dst = new NeighborLoop[neighborLists.Length];

            dst[0].startIdx = 0;
            dst[0].count = neighborLists[0].Length;

            for (int i = 1; i < neighborLists.Length; i++)
            {
                dst[i].startIdx = dst[i - 1].startIdx + dst[i - 1].count;
                dst[i].count = neighborLists[i].Length;
            }

            return dst;
        }

        static int[] generateNeighborIdxs(Neighbor[][] neighborLists)
        {
            int sum = 0;
            foreach (var nl in neighborLists)
            {
                sum += nl.Length;
            }

            var dst = new int[sum * 3];

            int idx = 0;
            foreach (var nl in neighborLists)
            {
                for (int i = 0; i < nl.Length; i++)
                {
                    dst[idx] = nl[i].v1;
                    dst[idx + 1] = nl[i].v2;
                    dst[idx + 2] = nl[i].v3;
                    idx += 3;
                }
            }

            return dst;
        }

        public void ReleaseBuffer()
        {
            if (cbNeighborLoops != null) cbNeighborLoops.Release();
            if (cbNeighborIdxs != null) cbNeighborIdxs.Release();
        }
    }
}