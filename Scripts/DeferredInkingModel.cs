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
            public Material material;
            [Range(0, 255)] public int meshID;
        }

        readonly static List<DeferredInkingModel> Instances = new List<DeferredInkingModel>();
        public static IReadOnlyList<DeferredInkingModel> GetInstances() { return Instances; }

        [Range(1, 255)] public int modelID = 255;
        public List<Mesh> meshes = new List<Mesh>();

        void OnEnable()
        {
            Instances.Add(this);
        }

        void OnDisable()
        {
            Instances.Remove(this);
        }
    }
}
