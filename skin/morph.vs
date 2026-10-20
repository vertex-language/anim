package skin

import (
    "math/geom"
    "mesh"
)

/// Morph is a morph target (a blend shape): how far some vertices of a
/// mesh move, and their normals turn, at weight 1. It's sparse: only the
/// vertices it moves are listed, so a nose target over a 15k-vertex body
/// costs a few hundred entries.
public struct Morph {
    public var Name: string
    /// The vertices it moves, ascending.
    public var Indices: [int32]
    /// Each one's offset at weight 1.
    public var Positions: [geom.Vec3]
    /// Each one's normal change at weight 1, or empty.
    public var Normals: [geom.Vec3]

    public init(_ name: string, indices: [int32], positions: [geom.Vec3], normals: [geom.Vec3] = []) {
        Name = name
        Indices = indices
        Positions = positions
        Normals = normals
    }

    /// Dense is a morph from an offset for every vertex, keeping only the
    /// ones that move more than `epsilon`.
    public static func Dense(_ name: string, positions: [geom.Vec3], normals: [geom.Vec3] = [], epsilon: float32 = 1e-6) -> Morph {
        var m = Morph(name, indices: [], positions: [], normals: [])
        let e2 = epsilon * epsilon
        for i in 0..<positions.count {
            let n = i < normals.count ? normals[i] : geom.Vec3.Zero
            if positions[i].LengthSquared() <= e2 && n.LengthSquared() <= e2 { continue }
            m.Indices.append(int32(i))
            m.Positions.append(positions[i])
            if !normals.isEmpty { m.Normals.append(n) }
        }
        return m
    }

    /// Offset is the morph with every index moved by `by`: for a mesh
    /// appended after others.
    public func Offset(_ by: int) -> Morph {
        var m = self
        for i in 0..<m.Indices.count { m.Indices[i] += int32(by) }
        return m
    }
}

/// Morphed is a mesh with morphs applied at weights (by index; missing or
/// zero weights are skipped). Normals are renormalized where they moved.
public func Morphed(_ base: mesh.Mesh, _ morphs: [Morph], _ weights: [float32]) -> mesh.Mesh {
    var out = base
    var touched = [bool](repeating: false, count: base.Normals.count)
    for (k, m) in morphs.enumerated() {
        let w = k < weights.count ? weights[k] : 0
        if w == 0 { continue }
        for j in 0..<m.Indices.count {
            let v = int(m.Indices[j])
            out.Positions[v] += m.Positions[j] * w
            if j < m.Normals.count && v < out.Normals.count {
                out.Normals[v] += m.Normals[j] * w
                touched[v] = true
            }
        }
    }
    for v in 0..<touched.count where touched[v] { out.Normals[v] = out.Normals[v].Normalized() }
    return out
}
