import UIKit

class ViewToggleButton: UIButton {
    override var isSelected: Bool {
        didSet {
            self.tintColor = Self.tintColorFor(isSelected: self.isSelected)
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)

        self.commonInit()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)

        self.commonInit()
    }

    private func commonInit() {
        self.tintColor = Self.tintColorFor(isSelected: self.isSelected)
        self.setBackgroundImage(nil, for: .selected)
    }

    private static func tintColorFor(isSelected: Bool) -> UIColor {
        let defaultTintColor: UIColor
        if #available(iOS 15.0, *) {
            defaultTintColor = .tintColor
        } else {
            defaultTintColor = UIView().tintColor!
        }

        return isSelected ? defaultTintColor : .red
    }
}
