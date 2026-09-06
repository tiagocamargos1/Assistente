import sys
from PIL import Image
S=1316/1721
def stitch(paths, offsets, out):
    W=round(1284*S); H=round(2778*S)
    canvas=Image.new('RGB',(W,H))
    for p,off in zip(paths,offsets):
        im=Image.open(p).convert('RGB')
        y=round(off*S)
        canvas.paste(im.crop((0,0,W,im.height)),(0,y))
    canvas=canvas.resize((1284,2778),Image.LANCZOS)
    canvas.save(out,'PNG')
    print(out,canvas.size)
if __name__=='__main__':
    out=sys.argv[1]; paths=sys.argv[2::2]; offs=[int(x) for x in sys.argv[3::2]]
    stitch(paths,offs,out)
