## TestAutopilot (preload("res://tests/_autopilot.gd")) - autopilot testów.
## Logika w scripts/path_steer.gd (PathSteer), wspólna z botem ekstremistą.


static func steer(car: StuntCar, off: float, head_err: float, curve := 0.0) -> float:
	return PathSteer.steer(car, off, head_err, curve)


static func beta_deg(car: RigidBody3D) -> float:
	return PathSteer.beta_deg(car)
