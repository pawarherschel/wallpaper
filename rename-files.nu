#!/usr/bin/env nu
#!nix-shell -i nu -p imagemagick

use std log

let seed = ("meow" | into binary | into int)

let temp_dir = "/tmp/wallpapers"
mkdir $temp_dir
let files = (ls *.png)

if ($files | is-empty) { 
    log warning "No .png files found."; exit 
}

log info "Processing"
let plan = ($files | enumerate | par-each {|it|
    let name = $it.item.name

    log info $"($name)"


    let fp_temp = ([$temp_dir $name $"($it.index)" "fingerprint.png"] | path join)
    let previews = ($fp_temp | path dirname)
    mkdir $previews
    
    let downsampled = ([$previews "downsampled.png"] | path join)
    let reduced     = ([$previews "reduced.png"    ] | path join)
    let strip       = ([$previews "strip.png"      ] | path join)
    let fp_enlarged = ([$previews "fp_enlarged.png"] | path join)

    let fingerprint = (
        magick
            $name
            -limit thread 1
            -colorspace oklab
            -seed $seed
            -resize 1920x1080!
            -write $downsampled
            -dither None
            -kmeans 16
            -write $reduced
            -filter cubic
            -distort Resize 16x9!
            -set colorspace sRGB
            -depth 8
            -write $fp_temp
            -colorspace oklch
            rgb:-
    )

    magick $fp_temp -set colorspace oklab -scale 1920x1080! $fp_enlarged

    magick $downsampled $reduced $fp_enlarged +append -splice 0x1 $strip

    let images = kitten icat --align left --transfer-mode stream $strip

    log info $"($it.index) ($images)"

    let hash = $fingerprint | encode hex

    let chunks = ($hash | split chars | chunks 32 | each { str join })
    let dirs = ($chunks | drop 1)
    let file = ($chunks | last | $in + ".png")
    let temp_path = [[$temp_dir] $dirs [$file]] | flatten | path join
    
    let bytes = ($hash | split chars | chunks 2 | each { str join | into int -r 16 })
    
    let triplets = ($bytes | chunks 3)
    
    let l = ($triplets | each { get 0 } | each { $in * $in } | math avg | math sqrt | math round -p 3)
    let c = ($triplets | each { get 1 } | math avg                                  | math round -p 3)
    let h = ($triplets | each { get 2 } | math median                               | math round -p 0)

    let metrics = {
        l: $l,
        h: $h,
        c: $c,
        hash: $hash
    }

    { name: $name, hash: $hash, temp_path: $temp_path, metrics: $metrics}
})

$plan
| each {|it|
    mkdir ($it.temp_path | path dirname )
    mv $it.name $it.temp_path
}

try {
    ls *.png
    | each {|it|
        mv $it.name $"(it.name).bak"
    }
}

let deduped = $plan
| group-by hash --to-table
| each {|it|
    $it.items
    | take 1
}
| flatten
| sort-by metrics.l metrics.h metrics.s
| enumerate
| insert new {|it|
    [
    ($"($it.index + 1)" | fill -a right -c '0' -w 3)
    ".png"
    ]
    | str join
    
}

let phash_dir = [$temp_dir "phash"] | path join
mkdir $phash_dir

$deduped
| each {|it|
    let out_path = [$phash_dir $it.new] | path join
    let header = $"P6\n16 9\n((2 ** 8) - 1)\n" | encode utf8
    let ppm_data = $header ++ ($it.item.hash | decode hex)
    $ppm_data
    | magick - -set colorspace oklab -colorspace sRGB -scale 512x288 $out_path

    mv $it.item.temp_path $"($it.new)"
}

log info "Updating README.md..."
$deduped
| sort-by new
| each {|it| $"# ($it.new)\n\n![($it.new)]\(($it.new)\)\n" } 
| str join "\n" 
| save -f README.md

log info "Done.\a"
