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

            public CurvatureShaderBuffer curvatureBuffer;

            public void init()
            {
                var m = mesh.GetComponent<MeshFilter>().sharedMesh;
                this.curvatureBuffer = new CurvatureShaderBuffer(m);
            }
        }
        public static List<DeferredInkingModel> Instances = new List<DeferredInkingModel>();

        [Range(1, 255)] public int modelID = 255;
        public List<Mesh> meshes = new List<Mesh>();

        void Start() { } //for Inspector ON_OFF

        void Awake()
        {
            for (int i = 0; i < meshes.Count; i++)
            {
                if (meshes[i].curvatureBuffer == null) meshes[i].init();
            }

            Instances.Add(this);
        }

        void OnDestroy()
        {
            Instances.Remove(this);
        }

    }
}
