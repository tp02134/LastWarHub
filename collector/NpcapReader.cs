using System;
using System.IO;
using System.Text;
using System.Collections.Generic;
using System.Runtime.InteropServices;

namespace LastwarHub {
public sealed class NpcapReader : IDisposable {
 [DllImport("kernel32.dll", CharSet=CharSet.Unicode)] static extern bool SetDllDirectory(string path);
 [DllImport("wpcap.dll", CallingConvention=CallingConvention.Cdecl)] static extern int pcap_findalldevs(out IntPtr list, StringBuilder error);
 [DllImport("wpcap.dll", CallingConvention=CallingConvention.Cdecl)] static extern void pcap_freealldevs(IntPtr list);
 [DllImport("wpcap.dll", CallingConvention=CallingConvention.Cdecl)] static extern IntPtr pcap_open_live(string name,int snap,int promisc,int timeout,StringBuilder error);
 [DllImport("wpcap.dll", CallingConvention=CallingConvention.Cdecl)] static extern int pcap_setnonblock(IntPtr handle,int enabled,StringBuilder error);
 [DllImport("wpcap.dll", CallingConvention=CallingConvention.Cdecl)] static extern int pcap_datalink(IntPtr handle);
 [DllImport("wpcap.dll", CallingConvention=CallingConvention.Cdecl)] static extern int pcap_compile(IntPtr handle,out Program program,string filter,int optimize,uint mask);
 [DllImport("wpcap.dll", CallingConvention=CallingConvention.Cdecl)] static extern int pcap_setfilter(IntPtr handle,ref Program program);
 [DllImport("wpcap.dll", CallingConvention=CallingConvention.Cdecl)] static extern void pcap_freecode(ref Program program);
 [DllImport("wpcap.dll", CallingConvention=CallingConvention.Cdecl)] static extern int pcap_next_ex(IntPtr handle,out IntPtr header,out IntPtr packet);
 [DllImport("wpcap.dll", CallingConvention=CallingConvention.Cdecl)] static extern void pcap_close(IntPtr handle);
 [StructLayout(LayoutKind.Sequential)] struct Device {public IntPtr next,name,description,addresses;public uint flags;}
 [StructLayout(LayoutKind.Sequential)] struct Program {public uint count;public IntPtr instructions;}
 sealed class Adapter {public IntPtr Handle;public int Link;}
 sealed class Flow {
  public long Next=-1; public DateTime Seen=DateTime.UtcNow,GapSince=DateTime.MinValue;
  public SortedDictionary<long,byte[]> Pending=new SortedDictionary<long,byte[]>();
  public List<byte> Buffer=new List<byte>();
 }
 readonly List<Adapter> adapters=new List<Adapter>();
 readonly Dictionary<string,Flow> flows=new Dictionary<string,Flow>();
 HashSet<string> allowed=new HashSet<string>();
 public long Packets {get;private set;} public long Frames {get;private set;} public long Gaps {get;private set;}
 public int InterfaceCount {get{return adapters.Count;}}
 public NpcapReader() : this(true) {}
 NpcapReader(bool initialize) {
  if(!initialize)return;
  SetDllDirectory(Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System),"Npcap"));
  IntPtr list;var err=new StringBuilder(256);
  if(pcap_findalldevs(out list,err)!=0)throw new Exception("Npcap interface enumeration failed: "+err);
  try {for(IntPtr p=list;p!=IntPtr.Zero;){
   var d=(Device)Marshal.PtrToStructure(p,typeof(Device));p=d.next;
   string name=Marshal.PtrToStringAnsi(d.name);var h=pcap_open_live(name,262144,0,50,err);
   if(h==IntPtr.Zero)continue;
   int link=pcap_datalink(h);if(link!=1 && link!=0 && link!=101 && link!=12){pcap_close(h);continue;}
   Program filter;
   if(pcap_compile(h,out filter,"tcp portrange 10000-13000",1,0xffffffff)!=0){pcap_close(h);continue;}
   int code=pcap_setfilter(h,ref filter);pcap_freecode(ref filter);
   if(code!=0 || pcap_setnonblock(h,1,err)!=0){pcap_close(h);continue;}
   adapters.Add(new Adapter{Handle=h,Link=link});
  }}finally{pcap_freealldevs(list);}
  if(adapters.Count==0)throw new Exception("No usable Npcap adapters. Check installation and administrator access.");
 }
 public void SetAllowed(string[] endpoints){allowed=new HashSet<string>(endpoints??new string[0]);}
 static int U16(byte[] b,int p){return (b[p]<<8)|b[p+1];}
 static uint U32(byte[] b,int p){return ((uint)b[p]<<24)|((uint)b[p+1]<<16)|((uint)b[p+2]<<8)|b[p+3];}
 static string IP(byte[] b,int p){return b[p]+"."+b[p+1]+"."+b[p+2]+"."+b[p+3];}
 public byte[][] Poll(){
  var ready=new List<byte[]>();
  foreach(var a in adapters){for(int i=0;i<2000;i++){
   IntPtr header,packet;int code=pcap_next_ex(a.Handle,out header,out packet);if(code==0 || code==-2)break;if(code<0)throw new Exception("Npcap adapter disconnected; restart collection.");
   int n=Marshal.ReadInt32(header,8);if(n<20||n>262144)continue;
   var bytes=new byte[n];Marshal.Copy(packet,bytes,0,n);Packets++;
   Consume(bytes,a.Link,ready);
  }}
  var expired=new List<string>();foreach(var f in flows)if((DateTime.UtcNow-f.Value.Seen).TotalSeconds>120)expired.Add(f.Key);
  foreach(string f in expired)flows.Remove(f);
  return ready.ToArray();
 }
 void Consume(byte[] b,int link,List<byte[]> ready){
  int ip=0;
  if(link==1){if(b.Length<14)return;int type=U16(b,12);ip=14;if(type==0x8100){if(b.Length<18)return;type=U16(b,16);ip=18;}if(type!=0x800)return;}
  else if(link==0){if(BitConverter.ToUInt32(b,0)!=2)return;ip=4;}
  if(b.Length<ip+20 || b[ip]>>4!=4 || b[ip+9]!=6)return;
  if((U16(b,ip+6)&0x3fff)!=0)return;
  int tcp=ip+(b[ip]&15)*4;if(b.Length<tcp+20)return;
  string source=IP(b,ip+12)+":"+U16(b,tcp),dest=IP(b,ip+16)+":"+U16(b,tcp+2),key=source+">"+dest;
  if(!allowed.Contains(key))return;
  int data=tcp+(b[tcp+12]>>4)*4,total=U16(b,ip+2),end=Math.Min(b.Length,total==0?b.Length:ip+total);
  if(data> end || data<tcp+20)return;
  Flow f;if(!flows.TryGetValue(key,out f)){f=new Flow();flows[key]=f;}
  uint raw=U32(b,tcp+4);
  if((b[tcp+13]&2)!=0){f=new Flow();f.Next=(long)raw+1;flows[key]=f;}
  if(end==data)return;f.Seen=DateTime.UtcNow;
  long seq=raw;if(f.Next>=0){long epoch=f.Next&~0xffffffffL;seq=epoch+raw;if(seq-f.Next>2147483648L)seq-=4294967296L;else if(f.Next-seq>2147483648L)seq+=4294967296L;}
  if(f.Next<0)f.Next=seq;
  var part=new byte[end-data];Buffer.BlockCopy(b,data,part,0,part.Length);
  if(seq+part.Length<=f.Next)return;
  if(!f.Pending.ContainsKey(seq)||f.Pending[seq].Length<part.Length)f.Pending[seq]=part;
  if(f.Pending.Count>512){f.Pending.Clear();f.Buffer.Clear();f.Next=-1;Gaps++;return;}
  while(f.Pending.Count>0){var it=f.Pending.GetEnumerator();it.MoveNext();var first=it.Current;
   if(first.Key>f.Next){if(f.GapSince==DateTime.MinValue)f.GapSince=DateTime.UtcNow;if((DateTime.UtcNow-f.GapSince).TotalSeconds<5)break;f.Buffer.Clear();f.Next=first.Key;Gaps++;}
   f.GapSince=DateTime.MinValue;f.Pending.Remove(first.Key);int skip=(int)Math.Max(0,f.Next-first.Key);
   if(skip<first.Value.Length){for(int j=skip;j<first.Value.Length;j++)f.Buffer.Add(first.Value[j]);f.Next=first.Key+first.Value.Length;}
  }
  Extract(f.Buffer,ready);
 }
 void Extract(List<byte> b,List<byte[]> ready){
  int p=0;
  while(b.Count-p>=6){
   byte flag=b[p];if(flag!=0x80&&flag!=0xb0&&flag!=0x88&&flag!=0xb8){p++;continue;}
   bool big=(flag&8)!=0,compressed=(flag&32)!=0;int head=big?5:3;if(compressed)head+=4;
   if(b.Count-p<head+(compressed?4:3))break;
   long n=big?((long)b[p+1]<<24)+((long)b[p+2]<<16)+((long)b[p+3]<<8)+b[p+4]:(b[p+1]<<8)+b[p+2];
   if(n<3||n>8388608){p++;continue;}
   int body=p+head;
   bool valid=compressed?(b[body]==0x28&&b[body+1]==0xb5&&b[body+2]==0x2f&&b[body+3]==0xfd):b[body]==18;
   if(!valid){p++;continue;}
   if(b.Count-p<head+n)break;
   ready.Add(b.GetRange(p,head+(int)n).ToArray());Frames++;p+=head+(int)n;
  }
  if(p>0)b.RemoveRange(0,p);if(b.Count>16777216){b.Clear();Gaps++;}
 }
 public void Dispose(){foreach(var a in adapters)pcap_close(a.Handle);adapters.Clear();flows.Clear();}
 public static byte[][] Replay(byte[][] packets,int link,string[] endpoints){
  using(var r=new NpcapReader(false)){r.SetAllowed(endpoints);var result=new List<byte[]>();foreach(var p in packets)r.Consume(p,link,result);return result.ToArray();}
 }
}
}
