def get_video_rotation_filter(degrees, direction="cw"):
    """
    Returns an ffmpeg video filter string for rotating a video.
    direction: 'cw' (clockwise) or 'ccw' (counter-clockwise)
    """
    try:
        angle = float(degrees)
        if direction == "ccw":
            angle = -angle
        angle_mod = angle % 360
        # Debug print for tracing
        print(f"[vid_tools] Calculating rotation filter: degrees={degrees}, direction={direction}, angle_mod={angle_mod}")
        if angle_mod in [90, -270]:
            return "transpose=1"
        elif angle_mod in [270, -90]:
            return "transpose=2"
        elif angle_mod in [180, -180]:
            return "transpose=2,transpose=2"
        else:
            radians = angle * 3.141592653589793 / 180.0
            return f"rotate={radians}:bilinear=1"
    except Exception as e:
        print(f"Error in get_video_rotation_filter: {e}")
        return None
