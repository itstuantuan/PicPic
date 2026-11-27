// Run from the PicPic root with swift tool/render_studies.swift.
// Articulated cutouts use the original mannequin photography and the catalog's guide coordinates.
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

typealias P = CGPoint
func p(_ x: Double, _ y: Double) -> P { P(x: x, y: y) }
func midpoint(_ a: P, _ b: P) -> P { p((a.x+b.x)/2,(a.y+b.y)/2) }
func length(_ a: P, _ b: P) -> Double { hypot(b.x-a.x,b.y-a.y) }
func direction(_ a: P, _ b: P) -> Double { atan2(b.y-a.y,b.x-a.x) }
func mask(_ points: [P]) -> CGPath {
    let path = CGMutablePath()
    path.addLines(between: points)
    path.closeSubpath()
    return path
}
struct Study: Decodable {
    let aspect: Double
    let steps: [String]
    let joints: [[String:[Double]]]
}
let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
func source(_ name: String) -> CGImage {
    let url = root.appendingPathComponent("assets/poses/"+name+".png")
    return CGImageSourceCreateImageAtIndex(CGImageSourceCreateWithURL(url as CFURL,nil)!,0,nil)!
}
let front = source("02-遮阳"), face = source("05-踮脚挥手"), rear = source("01-回眸")
struct Part {
    let image: CGImage
    let region: CGPath
    let pivot: P
    let tip: P
    init(_ image: CGImage,_ pivot: P,_ tip: P,_ boundary: [P]) {
        self.image=image; self.pivot=pivot; self.tip=tip; region=mask(boundary)
    }
    func paint(_ c: CGContext, from a: P, to b: P, width: Double, mirror: Bool=false) {
        c.saveGState()
        c.translateBy(x:a.x,y:a.y)
        c.rotate(by:direction(a,b)-Double.pi/2)
        c.scaleBy(x:mirror ? -width : width, y:length(a,b)/length(pivot,tip))
        c.rotate(by:Double.pi/2-direction(pivot,tip))
        c.translateBy(x:-pivot.x,y:-pivot.y)
        c.addPath(region);c.clip()
        let height=340*Double(image.height)/Double(image.width)
        c.translateBy(x:0,y:height);c.scaleBy(x:1,y:-1)
        c.draw(image,in:CGRect(x:0,y:0,width:340,height:height))
        c.restoreGState()
    }
}
let head=Part(face,p(157,61),p(157,117),[p(110,1),p(207,1),p(207,61),p(192,98),p(177,105),p(169,109),p(160,112),p(151,112),p(143,108),p(120,97),p(112,73)])
let backHead=Part(rear,p(162,62),p(162,120),[p(108,4),p(214,4),p(214,115),p(188,114),p(182,137),p(139,138),p(142,107),p(111,87)])
let torso=Part(front,p(167,161),p(166,340),[p(146,108),p(187,108),p(191,132),p(221,145),p(221,192),p(217,209),p(207,248),p(210,278),p(231,317),p(232,322),p(223,322),p(213,325),p(201,332),p(190,342),p(181,354),p(175,368),p(173,375),p(158,375),p(154,366),p(148,355),p(139,344),p(129,335),p(118,327),p(106,323),p(98,323),p(119,280),p(122,249),p(106,197),p(102,177),p(116,156),p(120,141),p(144,132)])
let backTorso=Part(rear,p(159,150),p(151,330),[p(142,113),p(182,115),p(184,125),p(174,135),p(163,151),p(162,173),p(175,194),p(179,225),p(184,252),p(187,277),p(200,305),p(209,321),p(177,350),p(150,371),p(130,377),p(106,368),p(102,347),p(114,315),p(147,277),p(151,256),p(145,226),p(119,198),p(117,179),p(119,147),p(141,127)])
let upper=Part(front,p(234,164),p(243,270),[p(222,145),p(234,146),p(248,154),p(257,178),p(261,256),p(259,271),p(251,282),p(237,283),p(229,274),p(221,233),p(219,206),p(222,191)])
let lower=Part(front,p(244,270),p(262,374),[p(230,269),p(234,262),p(246,259),p(256,264),p(265,281),p(273,333),p(274,380),p(255,383),p(247,350),p(237,307)])
let palm=Part(front,p(262,375),p(254,451),[p(254,369),p(272,369),p(283,396),p(282,464),p(246,462),p(246,426),p(248,404),p(252,391),p(252,380)])
let waving=Part(face,p(71,157),p(55,85),[p(28,75),p(100,74),p(109,108),p(110,134),p(86,151),p(83,164),p(61,164),p(57,152),p(30,116)])
let thigh=Part(front,p(201,346),p(198,531),[p(180,352),p(197,334),p(215,324),p(229,323),p(239,350),p(243,395),p(236,452),p(218,515),p(215,537),p(209,546),p(185,546),p(177,537),p(172,506),p(168,426),p(170,382)])
let calf=Part(front,p(198,530),p(189,715),[p(177,524),p(183,516),p(196,512),p(209,516),p(216,525),p(216,543),p(225,576),p(225,605),p(212,661),p(202,712),p(202,723),p(175,723),p(177,698),p(176,654),p(170,615),p(171,582),p(177,548)])
let foot=Part(front,p(189,716),p(199,777),[p(176,712),p(202,712),p(203,739),p(225,772),p(226,791),p(172,792),p(172,755)])

func drawFigure(_ coords:[String:[Double]],_ c:CGContext,_ w:Int,_ h:Int,action:String) {
    let joints=coords.mapValues{p($0[0]*Double(w),$0[1]*Double(h))}
    func j(_ name:String)->P {joints[name]!}
    let shoulder=midpoint(j("ls"),j("rs")), hip=midpoint(j("lh"),j("rh"))
    let unit=length(j("ls"),j("rs"))/130
    let back=action.contains("背身")
    func continuation(_ from:P,_ end:P,_ distance:Double)->P {
        let factor=distance/max(1,length(from,end))
        return p(end.x+(end.x-from.x)*factor,end.y+(end.y-from.y)*factor)
    }
    func leg(_ side:String){
        let h=j(side+"h"),k=j(side+"k"),a=j(side+"a"),mirror=side=="l"
        let end=p(a.x+(mirror ? -7:7)*unit,a.y+27*unit)
        foot.paint(c,from:a,to:end,width:unit,mirror:mirror)
        calf.paint(c,from:k,to:a,width:unit,mirror:mirror)
        thigh.paint(c,from:h,to:k,width:unit,mirror:mirror)
    }
    func arm(_ side:String){
        let s=j(side+"s"),e=j(side+"e"),w=j(side+"w"), mirror=side=="l"
        upper.paint(c,from:s,to:e,width:unit,mirror:mirror)
        lower.paint(c,from:e,to:w,width:unit,mirror:mirror)
        let open=action.contains("招呼") || action.contains("舒展") || action.contains("摊开")
        (open ? waving:palm).paint(c,from:w,to:continuation(e,w,39*unit),width:unit,mirror:open ? !mirror:mirror)
    }
    leg("r"); leg("l")
    (back ? backTorso:torso).paint(c,from:shoulder,to:hip,width:back ? unit*1.12:unit)
    let neckTarget=continuation(shoulder,j("head"),-55*unit)
    (back ? backHead:head).paint(c,from:j("head"),to:neckTarget,width:unit)
    arm("r"); arm("l")
}
let out=root.appendingPathComponent("assets/studies")
let records=try JSONDecoder().decode([String:Study].self,from:Data(contentsOf:out.appendingPathComponent("landmarks.json")))
for (id,study) in records {
    let h=600,w=Int((Double(h)*study.aspect).rounded())
    let c=CGContext(data:nil,width:w,height:h,bitsPerComponent:8,bytesPerRow:0,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
    c.translateBy(x:0,y:Double(h));c.scaleBy(x:1,y:-1);c.interpolationQuality = .high
    for (i,person) in study.joints.enumerated(){drawFigure(person,c,w,h,action:study.joints.count==1 ? study.steps.joined():study.steps[i+1])}
    let file=out.appendingPathComponent(id+".png")
    let dest=CGImageDestinationCreateWithURL(file as CFURL,UTType.png.identifier as CFString,1,nil)!
    CGImageDestinationAddImage(dest,c.makeImage()!,nil)
    precondition(CGImageDestinationFinalize(dest))
}
