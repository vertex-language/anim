// Package skin is linear blend skinning: each vertex of a mesh follows up
// to four bones by weight. It turns a skeleton's bone matrices into a
// palette (each bone's motion from rest) and deforms meshes on the CPU;
// a renderer can upload the same palette and deform on the GPU.
package skin

import (
    "anim"
    "math/geom"
    "mesh"
)

/// Influences is how many bones a vertex follows.
public let Influences = 4

/// Skin binds a mesh to a skeleton.
public struct Skin {
    /// Four bone indices per vertex.
    public var Joints: [uint16] = []
    /// Four weights per vertex, summing to 1.
    public var Weights: [float32] = []
    /// Per bone: from the mesh's space at rest into the bone's own space.
    public var InverseBind: [geom.Mat4] = []

    public init() {}

    public init(joints: [uint16], weights: [float32], inverseBind: [geom.Mat4]) {
        Joints = joints
        Weights = weights
        InverseBind = inverseBind
    }

    /// VertexCount is how many vertices it binds.
    public var VertexCount: int { return Joints.count / Influences }
}

/// InverseBind is the inverse bind matrices for a skeleton whose bones
/// have the model's axes (anim.Skeleton(_:parents:at:)), with the mesh in
/// model space at rest: each joint's rest position, undone.
public func InverseBind(_ s: anim.Skeleton) -> [geom.Mat4] {
    var out: [geom.Mat4] = []
    for p in s.RestPositions() { out.append(geom.Translation(-p)) }
    return out
}

extension Skin {
    /// Palette is each bone's matrix times its inverse bind: what moves a
    /// vertex from rest to the pose. Upload it for GPU skinning.
    public func Palette(_ matrices: [geom.Mat4]) -> [geom.Mat4] {
        var out: [geom.Mat4] = []
        out.reserveCapacity(matrices.count)
        for i in 0..<matrices.count { out.append(matrices[i] * InverseBind[i]) }
        return out
    }

    /// Normalize makes each vertex's weights sum to 1 (a vertex with none
    /// follows bone 0).
    public mutating func Normalize() {
        var v = 0
        while v < VertexCount {
            let k = v * Influences
            var sum: float32 = 0
            for j in 0..<Influences { sum += Weights[k + j] }
            if sum <= 0 {
                Weights[k] = 1
                Joints[k] = 0
            } else {
                for j in 0..<Influences { Weights[k + j] /= sum }
            }
            v += 1
        }
    }

    /// Deform is the mesh moved by a palette: positions and normals.
    public func Deform(_ m: mesh.Mesh, _ palette: [geom.Mat4]) -> mesh.Mesh {
        var out = m
        for v in 0..<m.Positions.count {
            let k = v * Influences
            var p = geom.Vec3.Zero
            var n = geom.Vec3.Zero
            for j in 0..<Influences {
                let w = Weights[k + j]
                if w <= 0 { continue }
                let b = palette[int(Joints[k + j])]
                p += b.TransformPoint(m.Positions[v]) * w
                if v < m.Normals.count { n += b.TransformDirection(m.Normals[v]) * w }
            }
            out.Positions[v] = p
            if v < m.Normals.count { out.Normals[v] = n.Normalized() }
        }
        return out
    }
}
