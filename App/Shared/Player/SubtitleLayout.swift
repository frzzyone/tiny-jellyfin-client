import CoreText
import PlayerCore

/// Subtitles are set in Helvetica Neue at 48 pt on a 1080-line picture (56 on a phone, whose
/// picture is small and close), scaled with the picture.
enum SubtitleFont {
    static let name = "HelveticaNeue"
    #if os(iOS)
    static let referenceSize: CGFloat = 56
    #else
    static let referenceSize: CGFloat = 48
    #endif
    static let referenceHeight: CGFloat = 1080
    static let minimumSize: CGFloat = 12

    static func font(forPictureHeight height: CGFloat) -> CTFont {
        CTFontCreateWithName(name as CFString, max(minimumSize, referenceSize * height / referenceHeight), nil)
    }
}

enum SubtitleLayout {
    /// Where the image is inside the player view: the video aspect-fitted and centred, as the
    /// display layer draws it, minus any black bars encoded into the frames themselves. The whole
    /// view when the video size is not known yet.
    static func pictureRect(video: CGSize?, in bounds: CGSize, bars: PictureBars? = nil) -> CGRect {
        let whole = CGRect(origin: .zero, size: bounds)
        guard let video, video.width > 0, video.height > 0, bounds.width > 0, bounds.height > 0 else { return whole }
        let scale = min(bounds.width / video.width, bounds.height / video.height)
        var rect = CGRect(x: (bounds.width - video.width * scale) / 2, y: (bounds.height - video.height * scale) / 2,
                          width: video.width * scale, height: video.height * scale)
        if let bars {
            let top = rect.height * bars.top, bottom = rect.height * bars.bottom
            rect = CGRect(x: rect.minX, y: rect.minY + top, width: rect.width, height: max(0, rect.height - top - bottom))
        }
        return rect
    }

    /// Where the whole video frame is drawn: aspect-fitted, or with `fill` covering the view and
    /// cropped. Picture subtitles are placed on this, bars included.
    static func frameRect(video: CGSize?, in bounds: CGSize, fill: Bool) -> CGRect {
        guard let video, video.width > 0, video.height > 0, bounds.width > 0, bounds.height > 0 else {
            return CGRect(origin: .zero, size: bounds)
        }
        let scale = fill ? max(bounds.width / video.width, bounds.height / video.height)
                         : min(bounds.width / video.width, bounds.height / video.height)
        return CGRect(x: (bounds.width - video.width * scale) / 2, y: (bounds.height - video.height * scale) / 2,
                      width: video.width * scale, height: video.height * scale)
    }
}
