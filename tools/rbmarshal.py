# Minimal Ruby Marshal 4.8 reader and writer for RGSS3 data
import struct


class RObj:
    def __init__(self, cls, attrs=None):
        self.cls = cls
        self.attrs = attrs if attrs is not None else {}

    def __getitem__(self, k):
        return self.attrs.get("@" + k)

    def get(self, k, default=None):
        return self.attrs.get("@" + k, default)

    def __repr__(self):
        return f"<{self.cls}>"


class RUser:
    def __init__(self, cls, data):
        self.cls = cls
        self.data = data


class RSym(str):
    pass


def text(v):
    if isinstance(v, bytes):
        for enc in ("utf-8", "cp932"):
            try:
                return v.decode(enc)
            except UnicodeDecodeError:
                pass
        return v.decode("utf-8", "replace")
    return v


class Reader:
    def __init__(self, data):
        self.d = data
        self.p = 2
        self.syms = []
        self.objs = []

    def byte(self):
        b = self.d[self.p]
        self.p += 1
        return b

    def long(self):
        c = struct.unpack_from("b", self.d, self.p)[0]
        self.p += 1
        if c == 0:
            return 0
        if 5 <= c <= 127:
            return c - 5
        if -128 <= c <= -5:
            return c + 5
        if c > 0:
            v = int.from_bytes(self.d[self.p:self.p + c], "little")
            self.p += c
            return v
        n = -c
        v = int.from_bytes(self.d[self.p:self.p + n], "little")
        self.p += n
        return v - (1 << (8 * n))

    def raw(self):
        n = self.long()
        b = self.d[self.p:self.p + n]
        self.p += n
        return b

    def sym(self):
        t = chr(self.byte())
        if t == ":":
            s = RSym(self.raw().decode("utf-8", "replace"))
            self.syms.append(s)
            return s
        if t == ";":
            return self.syms[self.long()]
        if t == "I":
            s = self.sym()
            for _ in range(self.long()):
                self.sym()
                self.read()
            return s
        raise ValueError("bad symbol " + t)

    def keep(self, o):
        self.objs.append(o)
        return o

    def read(self):
        t = chr(self.byte())
        if t == "0":
            return None
        if t == "T":
            return True
        if t == "F":
            return False
        if t == "i":
            return self.long()
        if t == ":":
            self.p -= 1
            return self.sym()
        if t == ";":
            return self.syms[self.long()]
        if t == "@":
            return self.objs[self.long()]
        if t == "I":
            v = self.read()
            for _ in range(self.long()):
                self.sym()
                self.read()
            return v
        if t == '"':
            return self.keep(self.raw())
        if t == "f":
            s = self.raw().split(b"\x00")[0].decode()
            v = float({"inf": "inf", "-inf": "-inf", "nan": "nan"}.get(s, s))
            return self.keep(v)
        if t == "l":
            sign = chr(self.byte())
            n = self.long()
            v = int.from_bytes(self.d[self.p:self.p + n * 2], "little")
            self.p += n * 2
            return self.keep(-v if sign == "-" else v)
        if t == "[":
            a = self.keep([])
            for _ in range(self.long()):
                a.append(self.read())
            return a
        if t in "{}":
            h = self.keep({})
            for _ in range(self.long()):
                k = self.read()
                h[k if not isinstance(k, list) else tuple(k)] = self.read()
            if t == "}":
                self.read()
            return h
        if t == "o":
            o = self.keep(RObj(self.sym()))
            for _ in range(self.long()):
                k = self.sym()
                o.attrs[k] = self.read()
            return o
        if t == "u":
            cls = self.sym()
            return self.keep(RUser(cls, self.raw()))
        if t == "U":
            cls = self.sym()
            o = self.keep(RObj(cls))
            o.attrs["_data"] = self.read()
            return o
        if t == "e":
            self.sym()
            return self.read()
        if t in "cm":
            return self.keep(RSym(self.raw().decode()))
        raise ValueError(f"unsupported type {t!r} at {self.p}")


def loads(data):
    if data[:2] != b"\x04\x08":
        raise ValueError("bad marshal header")
    return Reader(data).read()


def load(path):
    with open(path, "rb") as f:
        return loads(f.read())


def w_long(n):
    if n == 0:
        return b"\x00"
    if 0 < n < 123:
        return struct.pack("b", n + 5)
    if -124 < n < 0:
        return struct.pack("b", n - 5)
    for size in range(1, 5):
        if 0 < n < (1 << (8 * size)):
            return struct.pack("b", size) + n.to_bytes(size, "little")
        if -(1 << (8 * size)) <= n < 0:
            return struct.pack("b", -size) + (n + (1 << (8 * size))).to_bytes(size, "little")
    raise ValueError("long too large")


class Writer:
    def __init__(self):
        self.out = bytearray(b"\x04\x08")
        self.syms = {}

    def sym(self, s):
        if s in self.syms:
            self.out += b";" + w_long(self.syms[s])
            return
        self.syms[s] = len(self.syms)
        b = s.encode()
        self.out += b":" + w_long(len(b)) + b

    def write(self, v):
        if v is None:
            self.out += b"0"
        elif v is True:
            self.out += b"T"
        elif v is False:
            self.out += b"F"
        elif isinstance(v, int):
            self.out += b"i" + w_long(v)
        elif isinstance(v, bytes):
            self.out += b'"' + w_long(len(v)) + v
        elif isinstance(v, str):
            b = v.encode("utf-8")
            self.out += b'I"' + w_long(len(b)) + b + w_long(1)
            self.sym("E")
            self.out += b"T"
        elif isinstance(v, list):
            self.out += b"[" + w_long(len(v))
            for x in v:
                self.write(x)
        else:
            raise TypeError(type(v))


def dumps(v):
    w = Writer()
    w.write(v)
    return bytes(w.out)
