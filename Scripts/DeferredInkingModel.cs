using System.Collections.Generic;
using UnityEngine;

namespace WCGL
{
    [ExecuteInEditMode]
    public class DeferredInkingModel : MonoBehaviour
    {
        public static List<DeferredInkingModel> Instances = new List<DeferredInkingModel>();

        [Range(1, 255)] public int modelID = 255;
        public List<LineMesh> meshes = new List<LineMesh>();

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
