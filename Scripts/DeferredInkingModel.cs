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

            private (Renderer original, UnityEngine.Mesh mesh, ComputeBuffer vertices) bakedMesh;

            public void bakeMesh(CommandBuffer commandBuffer)
            {
                if (mesh == null) return;

                var smr = mesh as SkinnedMeshRenderer;
                if (smr != null)
                {
                    if (bakedMesh.mesh == null) bakedMesh.mesh = new UnityEngine.Mesh();
                    smr.BakeMesh(bakedMesh.mesh);
                }
                else if(bakedMesh.original != mesh)
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

            ~Mesh()
            {
                bakedMesh.vertices?.Release();
            }
        }

        public static List<DeferredInkingModel> Instances = new List<DeferredInkingModel>();

        [Range(1, 255)] public int modelID = 255;
        public List<Mesh> meshes = new List<Mesh>();

        void Start() { } //for Inspector ON_OFF

        void Awake()
        {
            Instances.Add(this);
        }

        void OnDestroy()
        {
            Instances.Remove(this);
        }
    }
}
