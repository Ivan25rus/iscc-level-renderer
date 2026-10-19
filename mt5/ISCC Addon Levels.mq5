#property copyright "ISCC"
#property version "1.13"
#property indicator_chart_window
#property indicator_plots 0

// Only owned chart objects and two local files are used. No trading functions.
const string PREFIX="ISCC_ADDON_TV_";
const string INPUT_FILE="iscc-addon-levels.csv";
const string ACK_FILE="iscc-addon-levels-ack.csv";

struct Marker {
   string id,revision,symbol,timeframe,tool,side;
   datetime time;
   double price;
   color lineColor;
};

color FromRgb(long rgb) {
   return (color)(((rgb & 255)<<16) | (rgb & 65280) | ((rgb>>16) & 255));
}

long ToRgb(color value) {
   long native=(long)value;
   return ((native & 255)<<16) | (native & 65280) | ((native>>16) & 255);
}

bool ReadLine(int handle,string &fields[]) {
   if(FileIsEnding(handle)) return false;
   string line=FileReadString(handle);
   StringReplace(line,"\r","");
   return StringSplit(line,'\t',fields)>0;
}

bool Load(Marker &markers[],string &generation,int &protocol) {
   int handle=FileOpen(INPUT_FILE,FILE_READ|FILE_TXT|FILE_ANSI|FILE_SHARE_READ,0,CP_UTF8);
   if(handle==INVALID_HANDLE) return false;
   string parts[];
   bool valid=ReadLine(handle,parts) && ArraySize(parts)==4 && parts[0]=="ISCC_CANDLE_LEVELS" && (parts[1]=="1" || parts[1]=="2");
   protocol=valid ? (int)StringToInteger(parts[1]) : 0;
   int count=valid ? (int)StringToInteger(parts[3]) : -1;
   if(!valid || count<0 || count>2000) {FileClose(handle);return false;}
   generation=parts[2];
   if(StringLen(generation)!=64) {FileClose(handle);return false;}
   ArrayResize(markers,count);
   for(int i=0;i<count;i++) {
      if(!ReadLine(handle,parts) || ArraySize(parts)!=(protocol==2 ? 9 : 8)) {valid=false;break;}
      markers[i].id=parts[0];markers[i].revision=parts[1];markers[i].symbol=parts[2];
      markers[i].timeframe=parts[3];markers[i].time=(datetime)StringToInteger(parts[4]);
      markers[i].price=StringToDouble(parts[5]);markers[i].tool=parts[6];markers[i].side=parts[7];
      long rgb=protocol==2 ? StringToInteger(parts[8]) : (markers[i].side=="high" ? 16737095 : 49151);
      if(rgb<0 || rgb>16777215) {valid=false;break;}
      markers[i].lineColor=FromRgb(rgb);
      if(StringLen(markers[i].id)!=24 || markers[i].price<=0 || !MathIsValidNumber(markers[i].price)
         || markers[i].time<=0 || (markers[i].tool!="line" && markers[i].tool!="ray")
         || (markers[i].side!="high" && markers[i].side!="low")) {valid=false;break;}
   }
   if(valid) valid=ReadLine(handle,parts) && ArraySize(parts)==3 && parts[0]=="END" && parts[1]==generation && (int)StringToInteger(parts[2])==count;
   FileClose(handle);
   return valid;
}

bool Contains(Marker &markers[],string name,string symbol) {
   for(int i=0;i<ArraySize(markers);i++)
      if(PREFIX+markers[i].id==name && markers[i].symbol==symbol) return true;
   return false;
}

bool Draw(long chart,Marker &marker) {
   string name=PREFIX+marker.id;
   // The user chose native full horizontal levels in MT5 for both TV tools.
   // MT5 itself draws their prices on its standard right-hand price scale.
   // Source candle/timeframe/side and the exact confirmed price remain intact.
   if(ObjectFind(chart,name)>=0 && (ENUM_OBJECT)ObjectGetInteger(chart,name,OBJPROP_TYPE)!=OBJ_HLINE)
      if(!ObjectDelete(chart,name)) return false;
   if(ObjectFind(chart,name)<0 && !ObjectCreate(chart,name,OBJ_HLINE,0,0,marker.price)) return false;
   if(!ObjectSetDouble(chart,name,OBJPROP_PRICE,0,marker.price)
      || !ObjectSetInteger(chart,name,OBJPROP_COLOR,marker.lineColor)
      || !ObjectSetInteger(chart,name,OBJPROP_WIDTH,1)
      || !ObjectSetInteger(chart,name,OBJPROP_STYLE,STYLE_SOLID)
      || !ObjectSetInteger(chart,name,OBJPROP_BACK,false)
      || !ObjectSetInteger(chart,name,OBJPROP_TIMEFRAMES,OBJ_ALL_PERIODS)
      || !ObjectSetInteger(chart,name,OBJPROP_SELECTABLE,false)
      || !ObjectSetInteger(chart,name,OBJPROP_SELECTED,false)
      || !ObjectSetInteger(chart,name,OBJPROP_HIDDEN,false)) return false;
   ObjectSetString(chart,name,OBJPROP_TOOLTIP,"TV → MT5 | "+marker.timeframe+" | "+marker.side+" | "+TimeToString(marker.time));
   // A queued ObjectCreate is not confirmation of an applied level.
   return ObjectFind(chart,name)==0 && (ENUM_OBJECT)ObjectGetInteger(chart,name,OBJPROP_TYPE)==OBJ_HLINE
      && MathAbs(ObjectGetDouble(chart,name,OBJPROP_PRICE,0)-marker.price)<0.00000001
      && (color)ObjectGetInteger(chart,name,OBJPROP_COLOR)==marker.lineColor
      && ObjectGetInteger(chart,name,OBJPROP_TIMEFRAMES)==OBJ_ALL_PERIODS
      && ObjectGetInteger(chart,name,OBJPROP_WIDTH)==1
      && ObjectGetInteger(chart,name,OBJPROP_STYLE)==STYLE_SOLID
      && !ObjectGetInteger(chart,name,OBJPROP_BACK);
}

int OnInit() {EventSetTimer(1);return INIT_SUCCEEDED;}
void OnDeinit(const int reason) {EventKillTimer();}
int OnCalculate(const int rates_total,const int prev_calculated,const datetime &time[],
   const double &open[],const double &high[],const double &low[],const double &close[],
   const long &tick_volume[],const long &volume[],const int &spread[]) {return rates_total;}

void OnTimer() {
   Marker markers[];string generation;int protocol;
   if(!Load(markers,generation,protocol)) return;
   bool cleanupReady=true;
   for(long chart=ChartFirst();chart>=0;chart=ChartNext(chart)) {
      bool changed=false;
      for(int j=ObjectsTotal(chart)-1;j>=0;j--) {
         string name=ObjectName(chart,j);
         if(StringFind(name,PREFIX)==0 && !Contains(markers,name,ChartSymbol(chart))) {
            if(!ObjectDelete(chart,name) || ObjectFind(chart,name)>=0) cleanupReady=false;
            changed=true;
         }
      }
      if(changed) ChartRedraw(chart);
   }
   if(!cleanupReady) return;
   int output=FileOpen(ACK_FILE,FILE_WRITE|FILE_TXT|FILE_ANSI|FILE_SHARE_READ,0,CP_UTF8);
   if(output==INVALID_HANDLE) return;
   FileWriteString(output,"ISCC_CANDLE_LEVELS_ACK\t"+IntegerToString(protocol)+"\t"+generation+"\t"+IntegerToString(ArraySize(markers))+"\n");
   for(int i=0;i<ArraySize(markers);i++) {
      bool found=false,ready=true;
      for(long chart=ChartFirst();chart>=0;chart=ChartNext(chart)) {
         if(ChartSymbol(chart)!=markers[i].symbol) continue;
         found=true;if(!Draw(chart,markers[i])) ready=false;
         ChartRedraw(chart);
      }
      if(!found) {
         long chart=ChartOpen(markers[i].symbol,PERIOD_M5);
         ready=chart>0 && Draw(chart,markers[i]);found=chart>0;
         if(chart>0) ChartRedraw(chart);
      }
      int digits=(int)SymbolInfoInteger(markers[i].symbol,SYMBOL_DIGITS);
      string row=markers[i].id+"\t"+markers[i].revision+"\t"+markers[i].symbol+"\t"
         +(found && ready ? "ready" : "pending")+"\t"+DoubleToString(markers[i].price,digits);
      if(protocol==2) row+="\t"+IntegerToString(ToRgb(markers[i].lineColor));
      FileWriteString(output,row+"\n");
   }
   FileWriteString(output,"END\t"+generation+"\t"+IntegerToString(ArraySize(markers))+"\n");
   FileClose(output);
}
