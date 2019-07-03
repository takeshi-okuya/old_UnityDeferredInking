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
        public struct Mesh
        {
            public Renderer mesh;
            [Range(0, 30)] public int meshID;
        }

        [System.Serializable]
        public class LineMaterial
        {
            public bool enable = true;
            public Material material;
            [Range(0, 7)] public int materialID;
            public List<Mesh> meshes = new List<Mesh>();
        }

        public static List<DeferredInkingModel> Instances = new List<DeferredInkingModel>();

        [Range(1, 255)] public int modelID = 255;
        public List<LineMaterial> lineMaterials = new List<LineMaterial>();

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
