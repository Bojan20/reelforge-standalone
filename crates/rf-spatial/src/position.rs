//! 3D position and orientation types

use serde::{Deserialize, Serialize};

/// 3D position in space
#[derive(Debug, Clone, Copy, PartialEq, Serialize, Deserialize)]
pub struct Position3D {
    /// X coordinate (left/right, positive = right)
    pub x: f32,
    /// Y coordinate (front/back, positive = front)
    pub y: f32,
    /// Z coordinate (up/down, positive = up)
    pub z: f32,
}

impl Position3D {
    /// Create new position
    pub fn new(x: f32, y: f32, z: f32) -> Self {
        Self { x, y, z }
    }

    /// Origin position
    pub fn origin() -> Self {
        Self::new(0.0, 0.0, 0.0)
    }

    /// Create from spherical coordinates
    ///
    /// # Arguments
    /// * `azimuth` - Horizontal angle in degrees (-180 to 180, 0 = front, positive = right)
    /// * `elevation` - Vertical angle in degrees (-90 to 90, positive = up)
    /// * `distance` - Distance from origin
    pub fn from_spherical(azimuth: f32, elevation: f32, distance: f32) -> Self {
        let az_rad = azimuth.to_radians();
        let el_rad = elevation.to_radians();

        let cos_el = el_rad.cos();

        Self {
            x: distance * az_rad.sin() * cos_el,
            y: distance * az_rad.cos() * cos_el,
            z: distance * el_rad.sin(),
        }
    }

    /// Convert to spherical coordinates
    pub fn to_spherical(&self) -> SphericalCoord {
        let distance = self.magnitude();
        if distance < 1e-10 {
            return SphericalCoord {
                azimuth: 0.0,
                elevation: 0.0,
                distance: 0.0,
            };
        }

        let azimuth = self.x.atan2(self.y).to_degrees();
        let elevation = (self.z / distance).asin().to_degrees();

        SphericalCoord {
            azimuth,
            elevation,
            distance,
        }
    }

    /// Get magnitude (distance from origin)
    pub fn magnitude(&self) -> f32 {
        (self.x * self.x + self.y * self.y + self.z * self.z).sqrt()
    }

    /// Normalize to unit vector
    pub fn normalize(&self) -> Self {
        let mag = self.magnitude();
        if mag < 1e-10 {
            return Self::new(0.0, 1.0, 0.0); // Default forward
        }
        Self::new(self.x / mag, self.y / mag, self.z / mag)
    }

    /// Linear interpolation
    pub fn lerp(&self, other: &Self, t: f32) -> Self {
        Self::new(
            self.x + (other.x - self.x) * t,
            self.y + (other.y - self.y) * t,
            self.z + (other.z - self.z) * t,
        )
    }

    /// Distance to another point
    pub fn distance_to(&self, other: &Self) -> f32 {
        let dx = other.x - self.x;
        let dy = other.y - self.y;
        let dz = other.z - self.z;
        (dx * dx + dy * dy + dz * dz).sqrt()
    }

    /// Dot product
    pub fn dot(&self, other: &Self) -> f32 {
        self.x * other.x + self.y * other.y + self.z * other.z
    }

    /// Cross product
    pub fn cross(&self, other: &Self) -> Self {
        Self::new(
            self.y * other.z - self.z * other.y,
            self.z * other.x - self.x * other.z,
            self.x * other.y - self.y * other.x,
        )
    }

    /// Rotate around Z axis (yaw)
    pub fn rotate_z(&self, angle_deg: f32) -> Self {
        let rad = angle_deg.to_radians();
        let cos = rad.cos();
        let sin = rad.sin();
        Self::new(
            self.x * cos - self.y * sin,
            self.x * sin + self.y * cos,
            self.z,
        )
    }

    /// Rotate around X axis (pitch)
    pub fn rotate_x(&self, angle_deg: f32) -> Self {
        let rad = angle_deg.to_radians();
        let cos = rad.cos();
        let sin = rad.sin();
        Self::new(
            self.x,
            self.y * cos - self.z * sin,
            self.y * sin + self.z * cos,
        )
    }

    /// Rotate around Y axis (roll)
    pub fn rotate_y(&self, angle_deg: f32) -> Self {
        let rad = angle_deg.to_radians();
        let cos = rad.cos();
        let sin = rad.sin();
        Self::new(
            self.x * cos + self.z * sin,
            self.y,
            -self.x * sin + self.z * cos,
        )
    }
}

impl Default for Position3D {
    fn default() -> Self {
        Self::origin()
    }
}

/// Spherical coordinates
#[derive(Debug, Clone, Copy, PartialEq, Serialize, Deserialize)]
pub struct SphericalCoord {
    /// Azimuth in degrees (-180 to 180)
    pub azimuth: f32,
    /// Elevation in degrees (-90 to 90)
    pub elevation: f32,
    /// Distance from origin
    pub distance: f32,
}

impl SphericalCoord {
    /// Create new spherical coordinate
    pub fn new(azimuth: f32, elevation: f32, distance: f32) -> Self {
        Self {
            azimuth,
            elevation,
            distance,
        }
    }

    /// Convert to Cartesian position
    pub fn to_cartesian(&self) -> Position3D {
        Position3D::from_spherical(self.azimuth, self.elevation, self.distance)
    }
}

/// Cartesian coordinates (same as Position3D but different semantic)
#[derive(Debug, Clone, Copy, PartialEq, Serialize, Deserialize)]
pub struct CartesianCoord {
    /// X coordinate
    pub x: f32,
    /// Y coordinate
    pub y: f32,
    /// Z coordinate
    pub z: f32,
}

impl CartesianCoord {
    /// Create new Cartesian coordinate
    pub fn new(x: f32, y: f32, z: f32) -> Self {
        Self { x, y, z }
    }

    /// Convert to Position3D
    pub fn to_position(&self) -> Position3D {
        Position3D::new(self.x, self.y, self.z)
    }
}

impl From<Position3D> for CartesianCoord {
    fn from(pos: Position3D) -> Self {
        Self::new(pos.x, pos.y, pos.z)
    }
}

impl From<CartesianCoord> for Position3D {
    fn from(coord: CartesianCoord) -> Self {
        Self::new(coord.x, coord.y, coord.z)
    }
}

/// Listener orientation (head rotation)
#[derive(Debug, Clone, Copy, PartialEq, Serialize, Deserialize)]
pub struct Orientation {
    /// Yaw in degrees (rotation around vertical axis)
    pub yaw: f32,
    /// Pitch in degrees (looking up/down)
    pub pitch: f32,
    /// Roll in degrees (head tilt)
    pub roll: f32,
}

impl Orientation {
    /// Create new orientation
    pub fn new(yaw: f32, pitch: f32, roll: f32) -> Self {
        Self { yaw, pitch, roll }
    }

    /// Forward-facing orientation
    pub fn forward() -> Self {
        Self::new(0.0, 0.0, 0.0)
    }

    /// Get forward vector
    pub fn forward_vector(&self) -> Position3D {
        Position3D::new(0.0, 1.0, 0.0)
            .rotate_x(self.pitch)
            .rotate_z(self.yaw)
    }

    /// Get up vector
    pub fn up_vector(&self) -> Position3D {
        Position3D::new(0.0, 0.0, 1.0)
            .rotate_x(self.pitch)
            .rotate_y(self.roll)
            .rotate_z(self.yaw)
    }

    /// Get right vector
    pub fn right_vector(&self) -> Position3D {
        Position3D::new(1.0, 0.0, 0.0)
            .rotate_y(self.roll)
            .rotate_z(self.yaw)
    }

    /// Transform a position from world space to listener space
    pub fn world_to_listener(&self, world_pos: &Position3D) -> Position3D {
        // Inverse rotation
        world_pos
            .rotate_z(-self.yaw)
            .rotate_x(-self.pitch)
            .rotate_y(-self.roll)
    }

    /// Create rotation matrix (3x3)
    pub fn rotation_matrix(&self) -> [[f32; 3]; 3] {
        let cy = self.yaw.to_radians().cos();
        let sy = self.yaw.to_radians().sin();
        let cp = self.pitch.to_radians().cos();
        let sp = self.pitch.to_radians().sin();
        let cr = self.roll.to_radians().cos();
        let sr = self.roll.to_radians().sin();

        [
            [cy * cr + sy * sp * sr, -cy * sr + sy * sp * cr, sy * cp],
            [cp * sr, cp * cr, -sp],
            [-sy * cr + cy * sp * sr, sy * sr + cy * sp * cr, cy * cp],
        ]
    }
}

impl Default for Orientation {
    fn default() -> Self {
        Self::forward()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_spherical_conversion() {
        // Front center
        let pos = Position3D::from_spherical(0.0, 0.0, 1.0);
        assert!((pos.x - 0.0).abs() < 0.001);
        assert!((pos.y - 1.0).abs() < 0.001);
        assert!((pos.z - 0.0).abs() < 0.001);

        // Right
        let pos = Position3D::from_spherical(90.0, 0.0, 1.0);
        assert!((pos.x - 1.0).abs() < 0.001);
        assert!((pos.y - 0.0).abs() < 0.01);
        assert!((pos.z - 0.0).abs() < 0.001);

        // Left
        let pos = Position3D::from_spherical(-90.0, 0.0, 1.0);
        assert!((pos.x - (-1.0)).abs() < 0.001);
        assert!((pos.y - 0.0).abs() < 0.01);
    }

    #[test]
    fn test_round_trip() {
        let original = Position3D::new(0.5, 0.7, 0.3);
        let spherical = original.to_spherical();
        let back = spherical.to_cartesian();

        assert!((original.x - back.x).abs() < 0.001);
        assert!((original.y - back.y).abs() < 0.001);
        assert!((original.z - back.z).abs() < 0.001);
    }

    #[test]
    fn test_orientation() {
        let orient = Orientation::forward();
        let forward = orient.forward_vector();

        assert!((forward.y - 1.0).abs() < 0.001);
    }
}
