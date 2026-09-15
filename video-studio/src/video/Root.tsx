import { Cover } from './Cover';
import { Composition, registerRoot } from 'remotion';
import { Film } from './Film';
import { emptyProject, FPS, timeline } from '../lib/project';
function Root() {
    return <><Composition id="KakawordCover" component={Cover} width={1080} height={1440} fps={30} durationInFrames={1} defaultProps={{ project: emptyProject }} /><Composition id="Kakaword" component={Film} width={1080} height={1920} fps={FPS} durationInFrames={240} defaultProps={{ project: emptyProject }} calculateMetadata={({ props }) => ({ durationInFrames: timeline(props.project).total })} /></>;
}
registerRoot(Root);
