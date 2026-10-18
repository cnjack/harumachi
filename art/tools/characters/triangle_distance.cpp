// Exact closest points on indexed triangles, accelerated by a double-precision BVH.
// Read-only QA helper: no Godot dependency, history or sampling approximation.
#include <algorithm>
#include <cmath>
#include <cstdint>
#include <limits>
#include <queue>
#include <vector>

namespace {
struct V {
    double x, y, z;
    V operator+(V b) const { return {x+b.x,y+b.y,z+b.z}; }
    V operator-(V b) const { return {x-b.x,y-b.y,z-b.z}; }
    V operator*(double s) const { return {x*s,y*s,z*s}; }
    double at(int axis) const { return axis==0 ? x : axis==1 ? y : z; }
};
double dot(V a,V b) { return a.x*b.x+a.y*b.y+a.z*b.z; }
V cross(V a,V b) { return {a.y*b.z-a.z*b.y,a.z*b.x-a.x*b.z,a.x*b.y-a.y*b.x}; }
V read(const double* p) { return {p[0],p[1],p[2]}; }
V lo(V a,V b) { return {std::min(a.x,b.x),std::min(a.y,b.y),std::min(a.z,b.z)}; }
V hi(V a,V b) { return {std::max(a.x,b.x),std::max(a.y,b.y),std::max(a.z,b.z)}; }
V edge(V p,V a,V b) {
    V e=b-a;
    double n=dot(e,e);
    double t=n>0 ? std::clamp(dot(p-a,e)/n,0.0,1.0) : 0;
    return a+e*t;
}
V triangle(V p,V a,V b,V c) {
    V n=cross(b-a,c-a);
    double n2=dot(n,n);
    double edge2=std::max({dot(b-a,b-a),dot(c-a,c-a),dot(c-b,c-b)});
    // Zero-area and numerically collinear faces still contribute their edges.
    if(n2>edge2*edge2*1e-30) {
        V q=p-n*(dot(p-a,n)/n2);
        if(dot(cross(b-a,q-a),n)>=0 && dot(cross(c-b,q-b),n)>=0 && dot(cross(a-c,q-c),n)>=0)
            return q;
    }
    V answer=edge(p,a,b);
    double best=dot(p-answer,p-answer);
    for(V q : {edge(p,b,c),edge(p,c,a)}) {
        double d=dot(p-q,p-q);
        if(d<best) { best=d; answer=q; }
    }
    return answer;
}
struct Face { V a,b,c,low,high,center; int64_t source; };
struct Node { V low,high; int begin,end,left=-1,right=-1; };
class Tree {
    std::vector<Face> faces;
    std::vector<Node> nodes;
    int build(int first,int end) {
        V low=faces[first].low,high=faces[first].high;
        V clow=faces[first].center,chigh=clow;
        for(int i=first+1;i<end;i++) {
            low=lo(low,faces[i].low); high=hi(high,faces[i].high);
            clow=lo(clow,faces[i].center); chigh=hi(chigh,faces[i].center);
        }
        int index=static_cast<int>(nodes.size());
        nodes.push_back({low,high,first,end});
        if(end-first<=8) return index;
        V span=chigh-clow;
        int axis=span.y>span.x ? 1 : 0;
        if(span.z>span.at(axis)) axis=2;
        int mid=first+(end-first)/2;
        std::nth_element(faces.begin()+first,faces.begin()+mid,faces.begin()+end,
            [axis](const Face& a,const Face& b) {
                double x=a.center.at(axis),y=b.center.at(axis);
                return x==y ? a.source<b.source : x<y;
            });
        int left=build(first,mid),right=build(mid,end);
        nodes[index].left=left; nodes[index].right=right;
        return index;
    }
    double bound(V p,int index) const {
        const Node& node=nodes[index];
        double sum=0;
        for(int axis=0;axis<3;axis++) {
            double v=p.at(axis),a=node.low.at(axis),b=node.high.at(axis);
            double d=v<a ? a-v : v>b ? v-b : 0;
            sum+=d*d;
        }
        return sum;
    }
public:
    Tree(const double* vertices,const int64_t* indices,int64_t count) {
        faces.reserve(count); nodes.reserve(count*2);
        for(int64_t i=0;i<count;i++) {
            V a=read(vertices+indices[i*3]*3),b=read(vertices+indices[i*3+1]*3),c=read(vertices+indices[i*3+2]*3);
            faces.push_back({a,b,c,lo(lo(a,b),c),hi(hi(a,b),c),(a+b+c)*(1.0/3),i});
        }
        build(0,static_cast<int>(count));
    }
    void query(V p,double& distance,int64_t& source,V& closest) const {
        using Entry=std::pair<double,int>;
        std::priority_queue<Entry,std::vector<Entry>,std::greater<Entry>> queue;
        queue.emplace(bound(p,0),0);
        double best=std::numeric_limits<double>::infinity();
        source=-1;
        while(!queue.empty()) {
            auto [lower,index]=queue.top(); queue.pop();
            if(lower>best) break;
            const Node& node=nodes[index];
            if(node.left<0) {
                for(int i=node.begin;i<node.end;i++) {
                    const Face& f=faces[i]; V q=triangle(p,f.a,f.b,f.c);
                    double d=dot(p-q,p-q);
                    if(d<best || (d==best && f.source<source)) { best=d;source=f.source;closest=q; }
                }
            } else {
                for(int child : {node.left,node.right}) {
                    double d=bound(p,child);
                    if(d<=best) queue.emplace(d,child);
                }
            }
        }
        distance=std::sqrt(best);
    }
};
}

extern "C" int triangle_closest(const double* vertices,const int64_t* faces,int64_t face_count,
    const double* queries,int64_t query_count,double* distances,int64_t* source_faces,double* closest) {
    if(face_count<=0 || face_count>std::numeric_limits<int>::max()/2 || query_count<0) return 1;
    try {
        Tree tree(vertices,faces,face_count);
        for(int64_t i=0;i<query_count;i++) {
            V p; tree.query(read(queries+i*3),distances[i],source_faces[i],p);
            closest[i*3]=p.x; closest[i*3+1]=p.y; closest[i*3+2]=p.z;
        }
    } catch(...) { return 2; }
    return 0;
}
