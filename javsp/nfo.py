"""与操作nfo文件相关的功能"""
import os
from datetime import datetime
from lxml.etree import tostring, CDATA
from lxml.builder import E


from javsp.datatype import MovieInfo
from javsp.config import Cfg


def write_nfo(info: MovieInfo, nfo_file):
    """将存储了影片信息的'info'写入到nfo文件中"""
    # NFO spec: https://kodi.wiki/view/NFO_files/Movies
    nfo = E.movie()
    dic = info.get_info_dic()
    
    # 获取文件相关信息
    video_file = getattr(info, 'video_file', None)
    poster_file = getattr(info, 'poster_file', None) 
    fanart_file = getattr(info, 'fanart_file', None)
    
    # plot - 剧情简介（使用CDATA包装）
    if info.plot:
        plot_elem = E.plot()
        plot_elem.text = CDATA(info.plot)
        nfo.append(plot_elem)
    
    # outline - 空元素
    nfo.append(E.outline())
    
    # lockdata - 设置为false
    nfo.append(E.lockdata('false'))
    
    # dateadded - 当前时间
    current_time = datetime.now().strftime('%Y-%m-%d %H:%M:%S')
    nfo.append(E.dateadded(current_time))

    # title - 使用单纯的标题，不包含番号
    if info.title:
        nfo.append(E.title(info.title))
    
    # actor - 女优信息
    if info.actress:
        for i in info.actress:
            actor_elem = E.actor(
                E.name(i),
                E.type('Actor')
            )
            # 如果有头像也添加
            if (info.actress_pics) and (i in info.actress_pics):
                actor_elem.append(E.thumb(info.actress_pics[i]))
            nfo.append(actor_elem)
    
    # director - 导演
    if info.director:
        nfo.append(E.director(info.director))
    
    # year - 发行年份
    if info.publish_date:
        year = info.publish_date.split('-')[0]
        nfo.append(E.year(year))
    
    # sorttitle - 排序标题（与标题相同）
    if info.title:
        nfo.append(E.sorttitle(info.title))
    
    # premiered - 首映日期
    if info.publish_date:
        nfo.append(E.premiered(info.publish_date))
    
    # releasedate - 发行日期
    if info.publish_date:
        nfo.append(E.releasedate(info.publish_date))

    # runtime - 运行时间（分钟）
    if info.duration:
        nfo.append(E.runtime(info.duration))
    
    # studio - 制作商
    if info.producer:
        nfo.append(E.studio(info.producer))
    
    # fileinfo - 文件信息（留空，由媒体中心自动填充）
    fileinfo = E.fileinfo(
        E.streamdetails(
            E.video(
                E.codec('h264'),
                E.micodec('h264'),
                E.bitrate('0'),
                E.width('1920'),
                E.height('1080'),
                E.aspect('16:9'),
                E.aspectratio('16:9'),
                E.framerate('29.97'),
                E.language('und'),
                E.scantype('progressive'),
                E.default('True'),
                E.forced('False'),
                E.duration(info.duration if info.duration else '0'),
                E.durationinseconds('0')
            ),
            E.audio(
                E.codec('aac'),
                E.micodec('aac'),
                E.bitrate('0'),
                E.language('und'),
                E.scantype('progressive'),
                E.channels('2'),
                E.samplingrate('48000'),
                E.default('True'),
                E.forced('False')
            )
        )
    )
    nfo.append(fileinfo)

    # poster - 海报文件名（.png格式）
    if poster_file:
        poster_filename = os.path.basename(poster_file)
        nfo.append(E.poster(poster_filename))
    
    # thumb - 缩略图（与poster相同）
    if poster_file:
        poster_filename = os.path.basename(poster_file)
        nfo.append(E.thumb(poster_filename))
    
    # fanart - 横版封面文件名（.jpg格式）
    if fanart_file:
        fanart_filename = os.path.basename(fanart_file)
        nfo.append(E.fanart(fanart_filename))
    
    # maker - 制作商（与studion相同）
    if info.producer:
        nfo.append(E.maker(info.producer))
    
    # label - 发行商
    if info.publisher:
        nfo.append(E.label(info.publisher))
    
    # num - 番号
    if info.dvdid:
        nfo.append(E.num(info.dvdid))
    elif info.cid:
        nfo.append(E.num(info.cid))
    
    # release - 发行日期
    if info.publish_date:
        nfo.append(E.release(info.publish_date))
    
    # cover - 封面图片URL
    if info.cover:
        nfo.append(E.cover(info.cover))
    
    # website - 影片网站链接
    if info.url:
        nfo.append(E.website(info.url))

    with open(nfo_file, 'wt', encoding='utf-8') as f:
        f.write(tostring(nfo, encoding='unicode', pretty_print=True,
                         doctype='<?xml version="1.0" encoding="utf-8" standalone="yes" ?>'))


if __name__ == "__main__":
    import pretty_errors
    pretty_errors.configure(display_link=True)
    info = MovieInfo(from_file=R'unittest\data\IPX-177 (javbus).json')
    write_nfo(info)
