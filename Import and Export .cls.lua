
local function hex_to_bin(hex_in) -- 16進表記の文字列をバイナリ形式の内部数値に変換
    local hex = string.gsub(hex_in, "%s", "") -- スペースの削除
    local hex_len = string.len(hex) -- 入力文字数
    local hex_split = {}            -- 1バイト分ずつテーブルに保存

    for i=1, hex_len do
        -- 入力文字列を2文字ずつ区切ってテーブルに保存
        local idx = math.ceil(i/2)
        if hex_split[idx] == nil then
            hex_split[idx] = hex:sub(i,i)
        else
            hex_split[idx] = hex_split[idx] .. hex:sub(i,i)
        end
    end

    local bin_out = ""  -- 出力するバイナリ

    for i=1, hex_len/2 do
        -- 小分けにした文字列をtonumber()で数値に変換した後string.pack()でバイナリに変換
        bin_out = bin_out .. string.pack("B",tonumber(hex_split[i],16))
    end
    return bin_out
end



local HEADER = "53 4c 43 43 00 01"   -- ヘッダ文字列

-- インポート
local function read_cls(path)
    if app.sprite == nil then
        print("アクティブなスプライトがないぜ！")
        return
    end
    if path == "" then
        return
    end

    local file_in = io.open(path,"rb")  -- ファイル読み込み
    if file_in == nil then
        return
    end
    local data = file_in:read("a")      -- 内容の読み込み
    io.close(file_in)

    local ptr = 1   -- ポインタ

    -- ヘッダのチェック
    local header_chk = ""
    for i=1, 6 do
        header_chk = header_chk .. string.pack("B",(string.byte(data, ptr)))
        ptr = ptr + 1
    end
    if header_chk ~= hex_to_bin(HEADER) then
        print("ヘッダ情報が不正だぜ!")
        return
    end

    -- MEMO: カラーセット名および色名の読み込みは不要なのでスキップ

    -- カラーセット名領域のバイト数を取得
    local cls_name_size = 0
    for i=1,4 do
        cls_name_size =  cls_name_size + string.byte(data, ptr)*(256^(i-1))
        ptr = ptr + 1
    end
    ptr = ptr + cls_name_size   -- カラーセット領域をスキップ

    -- カラーセット名領域後の固定4ビットをチェック
    local cls_name_chk = ""
    for i=1,4 do
        cls_name_chk = cls_name_chk .. string.pack("B",(string.byte(data, ptr)))
        ptr = ptr + 1
    end
    if cls_name_chk ~= hex_to_bin("04 00 00 00") then
        print("カラーセット名が不正だぜ!")
        return
    end

    -- 色数を取得
    local color_size = 0
    for i=1,4 do
        color_size =  color_size + string.byte(data, ptr)*(256^(i-1))
        ptr = ptr + 1
    end
    ptr = ptr + 4       -- 色情報領域全体のバイト数は取得の必要なし

    local colors = {}      -- 色情報を保存するテーブル
    for c=1, color_size do
        -- 各色情報領域のバイト数を取得
        local color_dat_size = 0
        for i=1,4 do
            color_dat_size =  color_dat_size + string.byte(data, ptr)*(256^(i-1))
            ptr = ptr + 1
        end
        local color_dat_endptr = ptr + color_dat_size   -- 1色分の情報領域の終了位置

        -- RGBAを取得
        local r = string.byte(data, ptr)    -- R
        ptr = ptr + 1
        local g = string.byte(data, ptr)    -- G
        ptr = ptr + 1
        local b = string.byte(data, ptr)    -- B
        ptr = ptr + 1
        local a = string.byte(data, ptr)    -- A
        ptr = ptr + 1

        -- RGBA領域後の固定4ビットをチェック
        local color_dat_chk = ""
        for i=1,4 do
            color_dat_chk = color_dat_chk .. string.pack("B",(string.byte(data, ptr)))
            ptr = ptr + 1
        end
        if color_dat_chk ~= hex_to_bin("00 00 00 00") and color_dat_chk ~= hex_to_bin("01 00 00 00") then
            print("色情報が不正だぜ!")
            return
        end

        ptr = color_dat_endptr  -- 色名は必要ないのでポインタを終了位置まで飛ばす

        colors[c] = Color{r=r, g=g, b=b, a=a}      -- テーブルに色情報を保存
    end

    local pal = Palette(color_size)     -- パレット
    --print(color_size)
    for i=1, color_size do
        pal:setColor(i-1,colors[i])
    end

    app.sprite:setPalette(pal)
end

-- エクスポート
local function save_cls(path)
    if app.sprite == nil then
        print("アクティブなスプライトがないぜ！")
        return
    end
    if path == "" then
        return
    end

    local file_out = io.open(path,"wb")
    if file_out == nil then
        return
    end
    local filename = path:match("([^\\]-)%.cls$")   -- ファイル名の取得
    -- MEMO: クリスタ上ではカラーセット名のSJIS部分は読み込まれない様子
    --       UTF-8部分だけちゃんと書いておけば大丈夫なのか？
    --       環境によってはSJISから読み込むこともありそうだが う～む
    
    local cls_name_utf8 = ""                        -- カラーセット名(UTF-8)
    for p, c in utf8.codes(filename) do
        cls_name_utf8 = cls_name_utf8 .. utf8.char(c)
    end
    local cls_name_utf8_size = cls_name_utf8:len()  -- カラーセット名(UTF-8)のバイト数
    local cls_name_size = 2+4+2+cls_name_utf8_size  -- カラーセット名領域のバイト数
    --print(cls_name_size)

    local pal = app.sprite.palettes[1]              -- 現在のパレットを取得
    local color_size = #pal                         -- パレットの色数を取得
    local COLOR_DAT_SIZE = 8                       -- 各色情報領域のバイト数(色名は指定しないのでバイト数は固定)
    local color_dat_all_size = (COLOR_DAT_SIZE+4)*color_size        -- 色情報領域全体のバイト数

    local color_dat = ""        -- 各色情報の保存
    for i=0, color_size-1 do
        color_dat = color_dat .. string.pack("<I", COLOR_DAT_SIZE)
        local col = pal:getColor(i)     -- 色の取得
        color_dat = color_dat .. string.pack("B", col.red)
        color_dat = color_dat .. string.pack("B", col.green)
        color_dat = color_dat .. string.pack("B", col.blue)
        color_dat = color_dat .. string.pack("B", col.alpha)
        color_dat = color_dat .. hex_to_bin("00 00 00 00")
    end


    local data = ""                     -- ファイルに書き込む内容
    data = data .. hex_to_bin(HEADER)   -- ヘッダ書き込み
    data = data .. string.pack("I4", cls_name_size)
    data = data .. hex_to_bin("00 00 00 00 00 00")
    data = data .. string.pack("I2", cls_name_utf8_size)
    data = data .. cls_name_utf8

    data = data .. hex_to_bin("04 00 00 00")
    data = data .. string.pack("I4", color_size)
    data = data .. string.pack("I4", color_dat_all_size)
    data = data .. color_dat

    file_out:write(data)                -- ファイルに出力
    io.close(file_out)
end

-- ダイアログ

local dlg = Dialog()
dlg:file {
    id = "file_i",
    label = ".cls File(load)",
    open = true,
    save = false,
    filetypes = {"cls"}
}
dlg:file {
    id = "file_o",
    label = ".cls File(save)",
    open = true,
    save = true,
    filetypes = {"cls"}
}
dlg:button{
    id = "ok",
    text = "OK"
}
dlg:show()

local dlg_result = Dialog()
dlg_result:label{
    label = dlg.data.file_i
}
if dlg.data.ok then
    --dlg_result:show()
    save_cls(dlg.data.file_o)
    read_cls(dlg.data.file_i)
end