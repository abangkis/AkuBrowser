package main

import (
	"fmt"
	"image"
	"image/color"
	"image/png"
	"os"
	"path/filepath"
)

var (
	transparent = color.NRGBA{0, 0, 0, 0}
	navy        = color.NRGBA{23, 32, 51, 255}
	blue        = color.NRGBA{70, 102, 235, 255}
	cyan        = color.NRGBA{54, 211, 190, 255}
	white       = color.NRGBA{255, 255, 255, 255}
)

func main() {
	browserRoot, err := os.Getwd()
	if err != nil {
		panic(err)
	}
	if len(os.Args) > 1 {
		browserRoot, err = filepath.Abs(os.Args[1])
		if err != nil {
			panic(err)
		}
	}
	workspaceRoot := filepath.Dir(browserRoot)
	bridgeIcons := filepath.Join(workspaceRoot, "AkuBridge", "icons")
	storeAssets := filepath.Join(browserRoot, "store", "assets")
	for _, directory := range []string{bridgeIcons, storeAssets} {
		if err := os.MkdirAll(directory, 0o755); err != nil {
			panic(err)
		}
	}
	for _, size := range []int{16, 32, 48, 128} {
		target := filepath.Join(bridgeIcons, fmt.Sprintf("icon-%d.png", size))
		if err := writePNG(target, renderIcon(size)); err != nil {
			panic(err)
		}
	}
	if err := writePNG(filepath.Join(storeAssets, "store-icon-128.png"), renderIcon(128)); err != nil {
		panic(err)
	}
}

func renderIcon(size int) image.Image {
	const scale = 4
	canvasSize := size * scale
	canvas := image.NewNRGBA(image.Rect(0, 0, canvasSize, canvasSize))
	fill(canvas, transparent)
	margin := float64(canvasSize) * 0.055
	roundedRect(canvas, margin, margin, float64(canvasSize)-margin, float64(canvasSize)-margin, float64(canvasSize)*0.225, navy)

	left := point{float64(canvasSize) * 0.285, float64(canvasSize) * 0.745}
	apex := point{float64(canvasSize) * 0.50, float64(canvasSize) * 0.245}
	right := point{float64(canvasSize) * 0.745, float64(canvasSize) * 0.745}
	width := float64(canvasSize) * 0.115
	thickLine(canvas, left, apex, width, blue)
	thickLine(canvas, apex, right, width, cyan)
	thickLine(
		canvas,
		point{float64(canvasSize) * 0.385, float64(canvasSize) * 0.585},
		point{float64(canvasSize) * 0.635, float64(canvasSize) * 0.585},
		float64(canvasSize)*0.075,
		white,
	)
	return downsample(canvas, size)
}

type point struct{ x, y float64 }

func thickLine(target *image.NRGBA, start, end point, width float64, value color.NRGBA) {
	minX := int(min(start.x, end.x) - width)
	maxX := int(max(start.x, end.x) + width)
	minY := int(min(start.y, end.y) - width)
	maxY := int(max(start.y, end.y) + width)
	for y := minY; y <= maxY; y++ {
		for x := minX; x <= maxX; x++ {
			if distanceToSegment(point{float64(x) + 0.5, float64(y) + 0.5}, start, end) <= width/2 {
				target.SetNRGBA(x, y, value)
			}
		}
	}
}

func distanceToSegment(value, start, end point) float64 {
	dx, dy := end.x-start.x, end.y-start.y
	lengthSquared := dx*dx + dy*dy
	if lengthSquared == 0 {
		return distance(value, start)
	}
	t := ((value.x-start.x)*dx + (value.y-start.y)*dy) / lengthSquared
	t = max(0, min(1, t))
	return distance(value, point{start.x + t*dx, start.y + t*dy})
}

func distance(a, b point) float64 {
	dx, dy := a.x-b.x, a.y-b.y
	return sqrt(dx*dx + dy*dy)
}

func roundedRect(target *image.NRGBA, left, top, right, bottom, radius float64, value color.NRGBA) {
	for y := int(top); y < int(bottom); y++ {
		for x := int(left); x < int(right); x++ {
			nearestX := max(left+radius, min(right-radius, float64(x)+0.5))
			nearestY := max(top+radius, min(bottom-radius, float64(y)+0.5))
			if distance(point{float64(x) + 0.5, float64(y) + 0.5}, point{nearestX, nearestY}) <= radius {
				target.SetNRGBA(x, y, value)
			}
		}
	}
}

func downsample(source *image.NRGBA, size int) *image.NRGBA {
	const scale = 4
	target := image.NewNRGBA(image.Rect(0, 0, size, size))
	for y := 0; y < size; y++ {
		for x := 0; x < size; x++ {
			var red, green, blueValue, alpha uint32
			for sampleY := 0; sampleY < scale; sampleY++ {
				for sampleX := 0; sampleX < scale; sampleX++ {
					value := source.NRGBAAt(x*scale+sampleX, y*scale+sampleY)
					red += uint32(value.R)
					green += uint32(value.G)
					blueValue += uint32(value.B)
					alpha += uint32(value.A)
				}
			}
			divisor := uint32(scale * scale)
			target.SetNRGBA(x, y, color.NRGBA{
				R: uint8(red / divisor), G: uint8(green / divisor),
				B: uint8(blueValue / divisor), A: uint8(alpha / divisor),
			})
		}
	}
	return target
}

func fill(target *image.NRGBA, value color.NRGBA) {
	for y := target.Bounds().Min.Y; y < target.Bounds().Max.Y; y++ {
		for x := target.Bounds().Min.X; x < target.Bounds().Max.X; x++ {
			target.SetNRGBA(x, y, value)
		}
	}
}

func writePNG(path string, value image.Image) error {
	file, err := os.Create(path)
	if err != nil {
		return err
	}
	defer file.Close()
	return png.Encode(file, value)
}

func sqrt(value float64) float64 {
	if value == 0 {
		return 0
	}
	estimate := value
	for index := 0; index < 12; index++ {
		estimate = (estimate + value/estimate) / 2
	}
	return estimate
}
